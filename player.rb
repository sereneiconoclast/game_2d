require 'chipmunk'
require 'gosu'
require 'zorder'

class Player
  attr_reader :conn, :body, :shape

  def initialize(conn)
    @conn = conn

    # Create the Body for the Player
    @body = CP::Body.new(10.0, 150.0)

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

  # Directly set the position of our Player
  def warp(x, y)
    puts "Warping to #{x}x#{y}"
    @body.p = CP::Vec2.new(x, y)
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
end

class ClientPlayer < Player
  def initialize(conn, window)
    super(conn)
    @image = Gosu::Image.new(window, "media/Starfighter.bmp", false)
  end

  def draw
    @image.draw_rot(@body.p.x, @body.p.y, ZOrder::Player, @body.a.radians_to_gosu)
  end
end
