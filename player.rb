require 'chipmunk'
require 'gosu'
require 'zorder'
require 'registerable'

class Player
  include Registerable
  attr_reader :conn, :player_name, :body, :shape

  def initialize(conn, player_name)
    @conn = conn
    @player_name = player_name
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
  end

  # Directly set the position and velocity of our Player
  def warp(x, y, x_vel=0.0, y_vel=0.0)
    puts "Warping to #{x}x#{y} going #{x_vel}x#{y_vel}"
    @body.p = CP::Vec2.new(x, y)
    @body.v = CP::Vec2.new(x_vel, y_vel)
    @body.activate
  end

  # Apply negative Torque; Chipmunk will do the rest
  # $SUBSTEPS is used as a divisor to keep turning rate constant
  # even if the number of steps per update are adjusted
  def turn_left
    @body.t -= 40000.0/$SUBSTEPS
  end

  # Apply positive Torque; Chipmunk will do the rest
  # $SUBSTEPS is used as a divisor to keep turning rate constant
  # even if the number of steps per update are adjusted
  def turn_right
    @body.t += 40000.0/$SUBSTEPS
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
    @moves << new_move
  end

  def dequeue_move
    return if @moves.empty?
    puts "Processing a move (#{@moves.size} in queue)"
    move = @moves.shift
    if %w(turn_left turn_right accelerate boost reverse).include? move
      send move.to_sym
    else
      puts "Invalid move: #{move}"
    end
  end

  # When a force or torque is set on a Body, it is cumulative
  # This means that the force you applied last SUBSTEP will compound with the
  # force applied this SUBSTEP; which is probably not the behavior you want
  # We reset the forces on the Player each SUBSTEP for this reason
  def reset_for_next_move
    @body.reset_forces
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
      :position => [ @body.p.x, @body.p.y ],
      :velocity => [ @body.v.x, @body.v.y ],
      :angle => @body.a,
      :angular_vel => @body.w
    }
  end

  def update_from_json(json)
    # Player name updates?
    x, y = json['position']
    x_vel, y_vel = json['velocity']
    @body.p = CP::Vec2.new(x, y)  # position
    @body.v = CP::Vec2.new(x_vel, y_vel) # velocity
    @body.a = json['angle']       # radians
    @body.w = json['angular_vel'] # radians/second
  end
end

class ClientPlayer < Player
  attr_reader :move

  def initialize(conn, player_name, window)
    super(conn, player_name)
    @window = window
    @image = Gosu::Image.new(window, "media/Starfighter.bmp", false)
    @move = nil
  end

  def draw
    @image.draw_rot(@body.p.x, @body.p.y, ZOrder::Player, @body.a.radians_to_gosu)
  end

  def handle_input_and_move
    reset_for_next_move

    # If our rotation gets crazy-high, slow it down
    # Otherwise allow the player to adjust it
    if body.w > 1.0
      turn_left true
    elsif body.w < -1.0
      turn_right true
    # Check keyboard
    elsif @window.button_down? Gosu::KbLeft
      turn_left
    elsif @window.button_down? Gosu::KbRight
      turn_right
    end

    if @window.button_down? Gosu::KbUp
      if ( (@window.button_down? Gosu::KbRightShift) || (@window.button_down? Gosu::KbLeftShift) )
        boost
      else
        accelerate
      end
    elsif @window.button_down? Gosu::KbDown
      reverse
    end
  end

  def reset_for_next_move
    super
    @move = nil
  end

  def turn_left(automatic = false)
    super()
    @move = :turn_left unless automatic
  end

  def turn_right(automatic = false)
    super()
    @move = :turn_right unless automatic
  end

  def boost
    super
    @move = :boost
  end

  def accelerate
    super
    @move = :accelerate
  end

  def reverse
    super
    @move = :reverse
  end
end
