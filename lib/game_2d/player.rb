require 'facets/kernel/try'
require 'gosu'
require 'game_2d/entity'
require 'game_2d/entity/pellet'
require 'game_2d/entity/block'
require 'game_2d/move/rise_up'
require 'game_2d/zorder'

# The base Player class representing what all Players have in common
# Moves can be enqueued by calling add_move
# Calling update() causes a move to be dequeued and executed, applying forces
# to the game object
#
# The server instantiates this class to represent each connected player
class Player < Entity
  include Comparable

  # Game ticks it takes before a block's HP is raised by 1
  BUILD_TIME = 7

  # Amount to decelerate each tick when braking
  BRAKE_SPEED = 4

  attr_accessor :player_name, :score
  attr_reader :build_block_id

  def initialize(player_name = "<unknown>")
    super
    @player_name = player_name
    @score = 0
    @moves = []
    @current_move = nil
    @falling = false
    @build_block_id = nil
    @build_level = 0
    @complex_move = nil
  end

  def sleep_now?; false; end

  def falling?; @falling; end

  def build_block_id=(new_id)
    @build_block_id = new_id.try(:to_sym)
  end

  def building?; @build_block_id; end

  def build_block
    return nil unless building?
    fail "Can't look up build_block when not in a space" unless @space
    @space[@build_block_id] or fail "Don't have build_block #{@build_block_id}"
  end

  def destroy!
    build_block.owner_id = nil if building?
  end

  # Pellets don't hit the originating player
  def transparent_to_me?(other)
    super ||
    (other == build_block) ||
    (other.is_a?(Pellet) && other.owner == self)
  end

  def update
    fail "No space set for #{self}" unless @space
    check_for_disown_block

    if @complex_move
      # returns true if more work to do
      return if @complex_move.update(self)
      @complex_move.on_completion(self)
      @complex_move = nil
    end

    underfoot = next_to(self.a + 180)
    if @falling = underfoot.empty?
      self.a = 0
      accelerate(0, 1)
    end

    args = @moves.shift
    case (current_move = args.delete(:move).to_sym)
      when :slide_left, :slide_right, :brake, :flip, :build, :rise_up
        send current_move unless @falling
      when :fire
        fire args[:x_vel], args[:y_vel]
      else
        puts "Invalid move for #{self}: #{current_move}, #{args.inspect}"
    end if args

    # Only go around corner if sitting on exactly one object
    if underfoot.size == 1
      other = underfoot.first
      # Figure out where corner is and whether we're about to reach or pass it
      corner, distance, overshoot, turn = going_past_entity(other.x, other.y)
      if corner
        original_speed = @x_vel.abs + @y_vel.abs
        original_dir = vector_to_angle
        new_dir = original_dir + turn

        # Make sure nothing occupies any space we're about to move through
        if opaque(
          @space.entities_overlapping(*corner) + next_to(new_dir, *corner)
        ).empty?
          # Move to the corner
          self.x_vel, self.y_vel = angle_to_vector(original_dir, distance)
          move

          # Turn and apply remaining velocity
          # Make sure we move at least one subpixel so we don't sit exactly at
          # the corner, and fall
          self.a += turn
          overshoot = 1 if overshoot.zero?
          self.x_vel, self.y_vel = angle_to_vector(new_dir, overshoot)
          move

          self.x_vel, self.y_vel = angle_to_vector(new_dir, original_speed)
        else
          # Something's in the way -- possibly in front of us, or possibly
          # around the corner
          move
        end
      else
        # Not yet reaching the corner -- or making a diagonal motion, for which
        # we can't support going around the corner
        move
      end
    else
      # Straddling two objects, or falling
      move
    end

    # Check again whether we've moved off of a block
    # we were building
    check_for_disown_block
  end

  def slide_left; slide(self.a - 90); end
  def slide_right; slide(self.a + 90); end

  def slide(dir)
    if opaque(next_to(dir)).empty?
      accelerate(*angle_to_vector(dir))
    else
      self.a = dir + 180
    end
  end

  def brake
    if @x_vel.zero?
      self.y_vel = brake_velocity(@y_vel)
    else
      self.x_vel = brake_velocity(@x_vel)
    end
  end

  def brake_velocity(v)
    return 0 if v.abs < BRAKE_SPEED
    sign = v <=> 0
    sign * (v.abs - BRAKE_SPEED)
  end

  def flip
    self.a += 180
  end

  # Create the actual pellet
  def fire(x_vel, y_vel)
    pellet = Entity::Pellet.new(@x, @y, 0, x_vel, y_vel)
    pellet.owner = self
    @space << pellet
  end

  # Create the actual block
  def build
    if building?
      @build_level += 1
      if @build_level >= BUILD_TIME
        @build_level = 0
        build_block.hp += 1
      end
    else
      bb = Entity::Block.new(@x, @y)
      bb.owner_id = registry_id
      bb.hp = 1
      @space << bb # generates an ID
      @build_block_id = bb.registry_id
      @build_level = 0
    end
  end

  def disown_block; $stderr.puts "#{self} disowning #{build_block}"; @build_block_id, @build_level = nil, 0; end

  def check_for_disown_block
    return unless building?
    return if @space.entities_overlapping(@x, @y).include?(build_block)
    build_block.owner_id = nil
    build_block.wake!
    disown_block
  end

  def rise_up
    @complex_move = Move::RiseUp.new(self)
  end

  # Accepts a hash, with a key :move => move_type
  def add_move(new_move)
    return unless new_move
    @moves << new_move
  end

  def to_s
    "#{player_name} (#{registry_id_safe}) at #{x}x#{y}"
  end

  def all_state
    super.unshift(player_name).push(
      score, build_block_id, @complex_move)
  end

  def as_json
    super.merge!(
      :player_name => player_name,
      :score => score,
      :build_block => @build_block_id,
      :complex_move => @complex_move.as_json
    )
  end

  def update_from_json(json)
    @player_name = json[:player_name]
    @score = json[:score]
    @build_block_id = json[:build_block].try(:to_sym)
    @complex_move = Serializable.from_json(json[:complex_move])
    super
  end

  def image_filename; "player.png"; end

  def draw_zorder; ZOrder::Player end

  def draw(window)
    super
    window.font.draw_rel(player_name,
      pixel_x + CELL_WIDTH_IN_PIXELS / 2, pixel_y, ZOrder::Text,
      0.5, 1.0, # Centered X; above Y
      1.0, 1.0, Gosu::Color::YELLOW)
  end
end
