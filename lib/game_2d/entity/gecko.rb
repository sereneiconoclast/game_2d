require 'facets/kernel/try'
require 'game_2d/entity'
require 'game_2d/entity/pellet'
require 'game_2d/entity/block'
require 'game_2d/move/rise_up'
require 'game_2d/player'

# A player object that can stick to walls and slide around corners
# Calling update() causes a move to be dequeued and executed, applying forces
# to the game object
class Entity

class Gecko < Entity
  include Player
  include Comparable

  MAX_HP = 1

  # Game ticks it takes before a block's HP is raised by 1
  BUILD_TIME = 7

  # Amount to decelerate each tick when braking
  BRAKE_SPEED = 4

  MOVES_FOR_KEY_HELD = {
    Gosu::KbLeft         => :slide_left,
    Gosu::KbA            => :slide_left,
    Gosu::KbRight        => :slide_right,
    Gosu::KbD            => :slide_right,
    Gosu::KbRightControl => :brake,
    Gosu::KbLeftControl  => :brake,
    Gosu::KbDown         => :build,
    Gosu::KbS            => :build,
  }

  attr_reader :hp, :build_block_id

  def initialize(player_name = "<unknown>")
    super
    initialize_player
    @player_name = player_name
    @score = 0
    @hp = MAX_HP
    @build_block_id = nil
    @build_level = 0
  end

  def hp=(p); @hp = [[p, MAX_HP].min, 0].max; end

  def sleep_now?; false; end

  def should_fall?; underfoot.empty?; end

  def build_block_id=(new_id)
    @build_block_id = new_id.try(:to_sym)
  end

  def building?; @build_block_id; end

  def build_block
    return nil unless building?
    fail "Can't look up build_block when not in a space" unless @space
    @space[@build_block_id] or fail "Don't have build_block #{@build_block_id}"
  end

  def harmed_by(other, damage=1)
    puts "#{self}: Ouch!"
    self.hp -= damage
    die if hp <= 0
  end

  def destroy!
    build_block.owner_id = nil if building?
  end

  def update
    fail "No space set for #{self}" unless @space
    check_for_disown_block

    return if perform_complex_move

    if falling = should_fall?
      self.a = 0
      space.fall(self)
    end

    args = next_move
    case (current_move = args.delete(:move).to_sym)
      when :slide_left, :slide_right, :brake, :flip, :build, :rise_up
        send current_move unless falling
      when :fire
        fire args[:x_vel], args[:y_vel]
      else
        puts "Invalid move for #{self}: #{current_move}, #{args.inspect}"
    end if args

    # Only go around corner if sitting on exactly one object
    blocks_underfoot = underfoot
    if blocks_underfoot.size == 1
      other = blocks_underfoot.first
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

  def brake; slow_by BRAKE_SPEED; end

  def flip; self.a += 180; end

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
      if @space << bb # generates an ID
        @build_block_id = bb.registry_id
        @build_level = 0
      end
    end
  end

  def disown_block; @build_block_id, @build_level = nil, 0; end

  def check_for_disown_block
    return unless building?
    return if @space.entities_overlapping(@x, @y).include?(build_block)
    build_block.owner_id = nil
    build_block.wake!
    disown_block
  end

  def rise_up
    self.complex_move = Move::RiseUp.new(self)
  end

  # Called by GameWindow
  # Should return the move to be sent via ClientConnection
  # (or nil)
  def generate_move_from_click(x, y)
    if y < cy # Firing up
      y_vel = -Math.sqrt(2 * (cy - y)).round
      x_vel = (cx - x) / y_vel
    else
      y_vel = 0
      if y == cy
        return if x == cx
        x_vel = (x <=> cx) * MAX_VELOCITY
      else
        range = x - cx
        x_vel = (Math.sqrt(1.0 / (2.0 * (y - cy))) * range).round
      end
    end
    [:fire, {:x_vel => x_vel, :y_vel => y_vel}]
  end

  # Called by GameWindow
  # Should return the move to be sent via ClientConnection
  # (or nil)
  # This is for queued keypresses, i.e. those that happen
  # on key-down only (just once for a press), not continuously
  # for as long as held down
  def move_for_keypress(keypress)
    case keypress
      when Gosu::KbUp, Gosu::KbW
        return building? ? :rise_up : :flip
    end
  end

  # Called by GameWindow
  # Should return a map where the keys are... keys, and the
  # values are the corresponding moves to be sent via
  # ClientConnection
  # This is for non-queued keypresses, i.e. those that happen
  # continuously for as long as held down
  def moves_for_key_held
    MOVES_FOR_KEY_HELD
  end

  def all_state
    # Player name goes first, so we can sort on that
    super.unshift(player_name).push(
      score, @hp, build_block_id, @complex_move)
  end

  def as_json
    super.merge!(
      :player_name => player_name,
      :score => score,
      :hp => @hp,
      :build_block => @build_block_id,
      :complex_move => @complex_move.as_json
    )
  end

  def update_from_json(json)
    @player_name = json[:player_name] if json[:player_name]
    @score = json[:score] if json[:score]
    @hp = json[:hp] if json[:hp]
    @build_block_id = json[:build_block].try(:to_sym) if json[:build_block]
    @complex_move = Serializable.from_json(json[:complex_move]) if json[:complex_move]
    super
  end

  def image_filename; "gecko.png"; end
end

end
