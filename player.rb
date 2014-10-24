require 'entity'
require 'entity/pellet'
require 'gosu'
require 'zorder'

# The base Player class representing what all Players have in common
# Moves can be enqueued by calling add_move
# Calling update() causes a move to be dequeued and executed, applying forces
# to the game object
#
# The server instantiates this class to represent each connected player
# The connection (conn) is the received one for that player
class Player < Entity
  include Comparable
  attr_reader :conn, :player_name
  attr_accessor :score, :build_block

  def initialize(space, conn, player_name)
    super(space, 0, 0)
    @conn = conn
    @player_name = player_name
    @score = 0
    @moves = []
    @current_move = nil
    @falling = false
    @build_level = 0
    @build_block = nil
  end

  def sleep_now?; false; end

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
    underfoot = next_to(self.a + 180)
    if @falling = underfoot.empty?
      self.a = 0
      accelerate(0, 1)
    end

    args = @moves.shift
    case (current_move = args.delete('move').to_sym)
      when :slide_left, :slide_right, :flip, :build
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

  def flip
    self.a += 180
  end

  # Called server-side to create the actual pellet
  def fire(x_vel, y_vel)
    pellet = Entity::Pellet.new(@space, @x, @y, 0, x_vel, y_vel)
    pellet.owner = self
    pellet.generate_id
    @space.game.add_npc pellet
  end

  # Called server-side to create the actual block
  def build
    case @build_level
      when 0
        return if @build_block
        @build_block = Entity::Block.new(@space, @x, @y)
        @build_block.owner = self
        @build_block.generate_id
        @space.game.add_npc @build_block
    end
    @build_level += 1
  end

  def disown_block; @build_level, @build_block = 0, nil; end

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

  # Called client-side to dequeue an input event
  def handle_input(window, pressed_buttons)
    return if @falling
    move = move_for_keypress(window, pressed_buttons)
    @conn.send_move move
    add_move move
  end

  # Check keyboard, return a motion symbol or nil
  #
  # This is only useful for actions we can safely process
  # client-side without a server round-trip.  That excludes
  # any action that creates another entity, since only the
  # server is allowed to generate registry IDs.
  def move_for_keypress(window, pressed_buttons)
    # Generated once for each keypress
    until pressed_buttons.empty?
      button = pressed_buttons.shift
      case button
        when Gosu::KbUp, Gosu::KbW then return :flip
        when Gosu::KbP then @conn.send_ping; return nil
        when Gosu::KbLeft, Gosu::KbRight, Gosu::KbA, Gosu::KbD # nothing
        else puts "Ignoring key #{button}"
      end
    end

    # Continuously-generated when key held down
    case
      when window.button_down?(Gosu::KbLeft), window.button_down?(Gosu::KbA)
        :slide_left
      when window.button_down?(Gosu::KbRight), window.button_down?(Gosu::KbD)
        :slide_right
      when window.button_down?(Gosu::KbDown), window.button_down?(Gosu::KbS)
        send_build
        nil
    end
  end

  def send_fire(x_vel, y_vel)
    @conn.send_move :fire, :x_vel => x_vel, :y_vel => y_vel
  end

  def send_build
    @conn.send_move :build
  end
end
