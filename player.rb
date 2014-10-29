require 'entity'
require 'entity/pellet'
require 'entity/block'
require 'gosu'
require 'zorder'

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

  attr_accessor :player_name, :score, :build_block

  def initialize(space, player_name)
    super(space, 0, 0)
    @player_name = player_name
    @score = 0
    @moves = []
    @current_move = nil
    @falling = false
    @build_block = nil
    @build_level = 0
    @move_fiber = nil
  end

  def self.from_json(space, json)
    player = Player.new(space, json['player_name'])
    player.registry_id = registry_id = json['registry_id']
    puts "Added player #{player}"
    player.update_from_json(json)
  end

  def sleep_now?; false; end

  def falling?; @falling; end

  def building?; @build_block; end

  def destroy!
    @build_block.owner = nil if @build_block
  end

  # Pellets don't hit the originating player
  def transparent_to_me?(other)
    super ||
    (other == @build_block) ||
    (other.is_a?(Pellet) && other.owner == self)
  end

  def update
    if @move_fiber
      return if @move_fiber.resume # more work to do
      @move_fiber = nil
      self.x_vel = self.y_vel = 0
    end

    underfoot = next_to(self.a + 180)
    if @falling = underfoot.empty?
      self.a = 0
      accelerate(0, 1)
    end

    args = @moves.shift
    case (current_move = args.delete('move').to_sym)
      when :slide_left, :slide_right, :brake, :flip, :build, :rise_up
        send current_move unless @falling
      when :fire # server-side only
        fire args['x_vel'], args['y_vel']
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

    # Now see if we've moved off of a block we were building
    if @build_block && !@space.entities_overlapping(@x, @y).include?(@build_block)
      @build_block.owner = nil
      disown_block
    end
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

  # Called server-side to create the actual pellet
  def fire(x_vel, y_vel)
    return unless $server
    pellet = Entity::Pellet.new(@space, @x, @y, 0, x_vel, y_vel)
    pellet.owner = self
    pellet.generate_id
    @space.game.add_npc pellet
  end

  # Called server-side to create the actual block
  def build
    return unless $server
    if @build_block
      @build_level += 1
      if @build_level >= BUILD_TIME
        @build_level = 0
        @build_block.hp += 1
      end
    else
      @build_block = Entity::Block.new(@space, @x, @y)
      @build_block.owner = self
      @build_block.hp = 1
      @build_block.generate_id
      @space.game.add_npc @build_block
      @build_level = 0
    end
  end

  def disown_block; @build_block, @build_level = nil, 0; end

  def rise_up
    @move_fiber = make_rise_up_fiber
  end

  # Fiber for executing a multi-tick "rise up" maneuver
  # 1) If not already at center of @build_block, move there @ 1 pixel/tick
  # 2) Rise exactly 1 cell @ 1 pixel/tick
  #
  # If step #2 is interrupted by an obstruction, repeat step #1 and stop
  # If at any point the @build_block is destroyed, simply abort
  #
  # Fiber returns true if it has more work to do, nil if it's finished
  #
  # Caller is responsible for zeroing velocity afterward
  def make_rise_up_fiber
    blok = @build_block
    start_x, start_y = blok.x, blok.y
    l = lambda do
      # step 1
      while x != start_x || y != start_y
        # abort if build_block destroyed
        return unless blok == @build_block

        self.x_vel = [[start_x - x, -PIXEL_WIDTH].max, PIXEL_WIDTH].min
        self.y_vel = [[start_y - y, -PIXEL_WIDTH].max, PIXEL_WIDTH].min
        move || return # move failed somehow
        Fiber.yield true
      end # end step 1

      self.x_vel, self.y_vel = angle_to_vector(self.a, PIXEL_WIDTH)
      CELL_WIDTH_IN_PIXELS.times do
        # abort if build_block destroyed
        return unless blok == @build_block

        move || break # move failed somehow, go to step 3
        Fiber.yield true
      end and return # done step 2

      # Step 2 failed.  Step 3: Repeat step 1
      while x != start_x || y != start_y
        # abort if build_block destroyed
        return unless blok == @build_block

        self.x_vel = [[start_x - x, -PIXEL_WIDTH].max, PIXEL_WIDTH].min
        self.y_vel = [[start_y - y, -PIXEL_WIDTH].max, PIXEL_WIDTH].min
        move || return # move failed somehow
        Fiber.yield true
      end # end step 3

      nil # done step 3
    end # lambda

    Fiber.new &l
  end

  def add_move(new_move, args={})
    return unless new_move
    return (@moves << new_move) if new_move.is_a?(Hash) # server side
    args['move'] = new_move
    @moves << args
  end

  def <=>(other)
    self.player_name <=> other.player_name
  end

  def to_s
    "#{player_name} (#{registry_id}) at #{x}x#{y}"
  end

  def as_json
    super().merge(
      :class => 'Player',
      :player_name => player_name,
      :score => score
    )
  end

  def update_from_json(json)
    @player_name = json['player_name']
    @score = json['score']
    super
  end

  def image_filename; "media/player.png"; end

  def draw_zorder; ZOrder::Player end

  def draw(window)
    super
    window.font.draw_rel(player_name,
      pixel_x + CELL_WIDTH_IN_PIXELS / 2, pixel_y, ZOrder::Text,
      0.5, 1.0, # Centered X; above Y
      1.0, 1.0, Gosu::Color::YELLOW)
  end
end
