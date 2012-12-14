require 'chipmunk'
require 'gosu'
require 'zorder'
require 'registerable'

# The base Player class representing what all Players have in common
# Moves can be enqueued by calling add_move
# Calling dequeue_move causes a move to be executed, applying forces
# to the game object
#
# The server instantiates this class to represent each connected player
# The connection (conn) is the received one for that player
class Player
  include Comparable
  include Registerable
  attr_reader :conn, :player_name, :body, :shape
  attr_accessor :score

  def initialize(conn, player_name)
    @conn = conn
    @player_name = player_name
    @score = 0
    @moves = []

    # Create the Body for the Player
    @body = CP::Body.new(10.0, 150.0)
    @body.object = self

    # In order to create a shape, we must first define it
    # Chipmunk defines 3 types of Shapes: Segments, Circles and Polys
    # We'll use s simple, 4 sided Poly for our Player (ship)
    # You need to define the vectors so that the "top" of the Shape is towards 0 radians (the right)
    shape_array = [
      CP::Vec2.new(-25.0, -25.0),
      CP::Vec2.new(-25.0, 25.0),
      CP::Vec2.new(25.0, 1.0),
      CP::Vec2.new(25.0, -1.0)
    ]
    @shape = CP::Shape::Poly.new(@body, shape_array, CP::Vec2.new(0, 0))

    # The collision_type of a shape allows us to set up special collision behavior
    # based on these types.  The actual value for the collision_type is arbitrary
    # and, as long as it is consistent, will work for us; of course, it helps to have it make sense
    @shape.collision_type = :ship

    @shape.e = 0.50 # elasticity

    @body.p = CP::Vec2.new(0.0, 0.0) # position
    @body.v = CP::Vec2.new(0.0, 0.0) # velocity

    # Keep in mind that down the screen is positive y, which means that PI/2 radians,
    # which you might consider the top in the traditional Trig unit circle sense is actually
    # the bottom; thus 3PI/2 is the top
    @body.a = (3*Math::PI/2.0) # angle in radians; faces towards top of screen

    @body.w_limit = 1.0
  end

  # Directly set the position and velocity of our Player
  def warp(x, y, x_vel=0.0, y_vel=0.0)
    puts "Warping to #{x}x#{y} going #{x_vel}x#{y_vel}"
    @body.p = CP::Vec2.new(x, y)
    @body.v = CP::Vec2.new(x_vel, y_vel)
    @body.activate
  end

  # When a force or torque is set on a Body, it is cumulative
  # This means that the force you applied last SUBSTEP will compound with the
  # force applied this SUBSTEP; which is probably not the behavior you want
  # We reset the forces on the Player each SUBSTEP for this reason
  def reset_for_next_move
    @body.reset_forces
  end

  # Apply negative Torque; Chipmunk will do the rest
  # $SUBSTEPS is used as a divisor to keep turning rate constant
  # even if the number of steps per update are adjusted
  #
  # This needs to be high enough to counteract gravity when the
  # player is sitting on the floor, or they may get stuck
  def turn_left
    @body.t -= 40000.0/$SUBSTEPS
  end

  # Apply positive Torque; Chipmunk will do the rest
  def turn_right
    @body.t += 40000.0/$SUBSTEPS
  end

  # Slow rotation by applying a torque in the opposite direction
  def slow_rotation
    # Stop spin completely if rotation less than half a degree
    if @body.w.abs < (Math::PI / 360.0)
      @body.w = 0.0
      return
    end

    amt = 500.0 * @body.w / $SUBSTEPS
    @body.t -= amt
  end

  # Apply forward force; Chipmunk will do the rest
  # $SUBSTEPS is used as a divisor to keep acceleration rate constant
  # even if the number of steps per update are adjusted
  # Here we must convert the angle (facing) of the body into
  # forward momentum by creating a vector in the direction of the facing
  # and with a magnitude representing the force we want to apply
  def accelerate
    @body.apply_force((@body.a.radians_to_vec2 * (3000.0/$SUBSTEPS)), CP::Vec2.new(0.0, 0.0))
  end

  # Apply even more forward force
  # See accelerate for more details
  def boost
    @body.apply_force((@body.a.radians_to_vec2 * (3000.0)), CP::Vec2.new(0.0, 0.0))
  end

  # Apply reverse force
  # See accelerate for more details
  def reverse
    @body.apply_force(-(@body.a.radians_to_vec2 * (1000.0/$SUBSTEPS)), CP::Vec2.new(0.0, 0.0))
  end

  def add_move(new_move)
    @moves << new_move if new_move
  end

  def dequeue_move
    reset_for_next_move
    slow_rotation

    return if @moves.empty?

    puts "#{@player_name} processing a move (#{@moves.size} in queue)"
    move = @moves.shift
    if [:turn_left, :turn_right, :accelerate, :boost, :reverse].include? move
      send move
      return move
    else
      puts "Invalid move for #{self}: #{move}"
      return nil
    end
  end

  def <=>(other)
    self.player_name <=> other.player_name
  end

  def to_s
    "#{player_name} (#{registry_id})"
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  def as_json
    {
      #JSON.create_id => self.class.name,
      :class => 'Player',
      :registry_id => registry_id,
      :player_name => player_name,
      :score => score,
      :position => [ @body.p.x, @body.p.y ],
      :velocity => [ @body.v.x, @body.v.y ],
      :angle => @body.a,
      :angular_vel => @body.w
    }
  end

  def update_from_json(json)
    @player_name = json['player_name']
    @score = json['score']
    x, y = json['position']
    x_vel, y_vel = json['velocity']
    @body.p = CP::Vec2.new(x, y)  # position
    @body.v = CP::Vec2.new(x_vel, y_vel) # velocity
    @body.a = json['angle']       # radians
    @body.w = json['angular_vel'] # radians/second
  end
end

# Subclass representing a player client-side
# Adds drawing capability
# We instantiate this class directly to represent remote players (not the one
# at the keyboard)
# Instances of this class will not have a connection (conn) because players
# aren't directly connected to each other
class ClientPlayer < Player
  def initialize(conn, player_name, window)
    super(conn, player_name)
    @window = window
    @image = Gosu::Image.new(window, "media/Starfighter.bmp", false)
  end

  def draw
    @image.draw_rot(@body.p.x, @body.p.y, ZOrder::Player, @body.a.radians_to_gosu)
  end
end

# Subclass representing the player at the controls of this client
# This is different in that we check the keyboard, and send moves
# to the server in addition to dequeueing them
class LocalPlayer < ClientPlayer
  def initialize(conn, player_name, window)
    super
  end

  def handle_input
    add_move move_for_keypress
  end

  # Check keyboard, return a motion symbol or nil
  def move_for_keypress
    case
    when @window.button_down?(Gosu::KbLeft) then :turn_left
    when @window.button_down?(Gosu::KbRight) then :turn_right
    when @window.button_down?(Gosu::KbUp) then
      if @window.button_down?(Gosu::KbRightShift) || @window.button_down?(Gosu::KbLeftShift)
        :boost
      else
        :accelerate
      end
    when @window.button_down?(Gosu::KbDown) then :reverse
    end
  end

  def dequeue_move
    @conn.send_move(super)
  end
end
