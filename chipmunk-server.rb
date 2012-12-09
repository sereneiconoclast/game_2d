## File: ChipmunkIntegration.rb
## Author: Dirk Johnson
## Version: 1.0.0
## Date: 2007-10-05
## License: Same as for Gosu (MIT)
## Comments: Based on the Gosu Ruby Tutorial, but incorporating the Chipmunk Physics Engine
## See https://github.com/jlnr/gosu/wiki/Ruby-Chipmunk-Integration for the accompanying text.

require 'rubygems'
require 'json'
require 'gosu'
require 'chipmunk'
require 'rev'

WORLD_WIDTH = 900
WORLD_HEIGHT = 600

HOSTNAME = 'localhost'
PORT = 4321

class PlayerConnection < Rev::TCPSocket
  def on_connect
    puts "#{object_id} -- #{remote_addr}:#{remote_port} connected"

    # Create the Body for the Player
    body = CP::Body.new(10.0, 150.0)
    
    # In order to create a shape, we must first define it
    # Chipmunk defines 3 types of Shapes: Segments, Circles and Polys
    # We'll use s simple, 4 sided Poly for our Player (ship)
    # You need to define the vectors so that the "top" of the Shape is towards 0 radians (the right)
    shape_array = [CP::Vec2.new(-25.0, -25.0), CP::Vec2.new(-25.0, 25.0), CP::Vec2.new(25.0, 1.0), CP::Vec2.new(25.0, -1.0)]
    shape = CP::Shape::Poly.new(body, shape_array, CP::Vec2.new(0,0))
    
    # The collision_type of a shape allows us to set up special collision behavior
    # based on these types.  The actual value for the collision_type is arbitrary
    # and, as long as it is consistent, will work for us; of course, it helps to have it make sense
    shape.collision_type = :ship

    shape.e = 0.50 # elasticity
    
    $space.add_body(body)
    $space.add_shape(shape)

    @player = Player.new(self, shape)
    x, y = WORLD_WIDTH / 2, WORLD_HEIGHT / 2 # start in the center of the world
    @player.warp(x, y)
    send_str = {'player_pos' => {'x' => x, 'y' => y}}.to_json
    len = send_str.size
    puts "Sending: #{send_str} (size: #{len})"
    write([len].pack "N")# 32-bit unsigned big-endian
    write send_str
  end

  def on_close
    puts "#{object_id} -- #{remote_addr}:#{remote_port} disconnected"
  end

  def on_read(data)
    write data
    puts "#{object_id} -- #{remote_addr}:#{remote_port} sent '#{data.chomp}'"
  end
end

# The number of steps to process every Gosu update
# The Player ship can get going so fast as to "move through" a
# star without triggering a collision; an increased number of
# Chipmunk step calls per update will effectively avoid this issue
SUBSTEPS = 6

# Convenience method for converting from radians to a Vec2 vector.
class Numeric
  def radians_to_vec2
    CP::Vec2.new(Math::cos(self), Math::sin(self))
  end
end

# This game will have one Player in the form of a ship
class Player
  attr_reader :shape

  def initialize(window, shape)
    @shape = shape
    @shape.body.p = CP::Vec2.new(0.0, 0.0) # position
    @shape.body.v = CP::Vec2.new(0.0, 0.0) # velocity
    
    # Keep in mind that down the screen is positive y, which means that PI/2 radians,
    # which you might consider the top in the traditional Trig unit circle sense is actually
    # the bottom; thus 3PI/2 is the top
    @shape.body.a = (3*Math::PI/2.0) # angle in radians; faces towards top of screen
  end
  
  # Directly set the position of our Player
  def warp(x, y)
    puts "Warping to #{x}x#{y}"
    @shape.body.p = CP::Vec2.new(x, y)
  end
  
  # Apply negative Torque; Chipmunk will do the rest
  # SUBSTEPS is used as a divisor to keep turning rate constant
  # even if the number of steps per update are adjusted
  def turn_left
    @shape.body.t -= 40000.0/SUBSTEPS
  end
  
  # Apply positive Torque; Chipmunk will do the rest
  # SUBSTEPS is used as a divisor to keep turning rate constant
  # even if the number of steps per update are adjusted
  def turn_right
    @shape.body.t += 40000.0/SUBSTEPS
  end
  
  # Apply forward force; Chipmunk will do the rest
  # SUBSTEPS is used as a divisor to keep acceleration rate constant
  # even if the number of steps per update are adjusted
  # Here we must convert the angle (facing) of the body into
  # forward momentum by creating a vector in the direction of the facing
  # and with a magnitude representing the force we want to apply
  def accelerate
    @shape.body.apply_force((@shape.body.a.radians_to_vec2 * (3000.0/SUBSTEPS)), CP::Vec2.new(0.0, 0.0))
  end
  
  # Apply even more forward force
  # See accelerate for more details
  def boost
    @shape.body.apply_force((@shape.body.a.radians_to_vec2 * (3000.0)), CP::Vec2.new(0.0, 0.0))
  end
  
  # Apply reverse force
  # See accelerate for more details
  def reverse
    @shape.body.apply_force(-(@shape.body.a.radians_to_vec2 * (1000.0/SUBSTEPS)), CP::Vec2.new(0.0, 0.0))
  end
end

# See how simple our Star is?
# Of course... it just sits around and looks good...
class Star
  attr_reader :shape
  
  def initialize(animation, shape)
    @animation = animation
    @color = Gosu::Color.new(0xff000000)
    @color.red = rand(255 - 40) + 40
    @color.green = rand(255 - 40) + 40
    @color.blue = rand(255 - 40) + 40
    @shape = shape
    @shape.body.p = CP::Vec2.new(rand * WORLD_WIDTH, rand * WORLD_HEIGHT) # position
    @shape.body.v = CP::Vec2.new(0.0, 0.0) # velocity
    @shape.body.a = (3*Math::PI/2.0) # angle in radians; faces towards top of screen
  end
end

class Game < Rev::TimerWatcher
  def initialize
    super(1.0 / 60.0, true) # Fire event 60 times a second
    attach(Rev::Loop.default)

    # Time increment over which to apply a physics "step" ("delta t")
    @dt = (1.0/60.0)
    
    # Create our Space and set its damping
    # A damping of 0.8 causes the ship bleed off its force and torque over time
    # This is not realistic behavior in a vacuum of space, but it gives the game
    # the feel I'd like in this situation
    $space = CP::Space.new
    # $space.damping = 0.8    
    $space.gravity = CP::Vec2.new(0.0, 10.0)

    # Walls all around the screen
    add_bounding_wall(WORLD_WIDTH / 2, 0.0, WORLD_WIDTH, 0.0)   # top
    add_bounding_wall(WORLD_WIDTH / 2, WORLD_HEIGHT, WORLD_WIDTH, 0.0) # bottom
    add_bounding_wall(0.0, WORLD_HEIGHT / 2, 0.0, WORLD_HEIGHT)   # left
    add_bounding_wall(WORLD_WIDTH, WORLD_HEIGHT / 2, 0.0, WORLD_HEIGHT) # right
    
    @players = []
    
    @stars = Array.new
        
    # Here we define what is supposed to happen when a Player (ship) collides with a Star
    # I create a @remove_shapes array because we cannot remove either Shapes or Bodies
    # from Space within a collision closure, rather, we have to wait till the closure
    # is through executing, then we can remove the Shapes and Bodies
    # In this case, the Shapes and the Bodies they own are removed in the Gosu::Window.update phase
    # by iterating over the @remove_shapes array
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @remove_shapes = []
    $space.add_collision_func(:ship, :star) do |ship_shape, star_shape|
      unless @remove_shapes.include? star_shape # filter out duplicate collisions
        @remove_shapes << star_shape
        # remember to return 'true' if we want regular collision handling
      end
    end
  end

  def add_bounding_wall(x_pos, y_pos, width, height)
    wall = CP::Body.new_static
    wall.p = CP::Vec2.new(x_pos, y_pos)
    wall.v = CP::Vec2.new(0.0, 0.0)
    wall.v_limit = 0.0 # max velocity (never move)
    shape = CP::Shape::Segment.new(wall,
      CP::Vec2.new(-0.5 * width, -0.5 * height),
      CP::Vec2.new(0.5 * width, 0.5 * height),
      1.0) # thickness
    shape.collision_type = :wall
    shape.e = 0.99 # elasticity (bounce)
    $space.add_body(wall)
    $space.add_shape(shape)
  end

  def on_timer
    # Step the physics environment SUBSTEPS times each update
    SUBSTEPS.times do
      # This iterator makes an assumption of one Shape per Star making it safe to remove
      # each Shape's Body as it comes up
      # If our Stars had multiple Shapes, as would be required if we were to meticulously
      # define their true boundaries, we couldn't do this as we would remove the Body
      # multiple times
      # We would probably solve this by creating a separate @remove_bodies array to remove the Bodies
      # of the Stars that were gathered by the Player
      @remove_shapes.each do |shape|
        @stars.delete_if { |star| star.shape == shape }
        $space.remove_body(shape.body)
        $space.remove_shape(shape)
      end
      @remove_shapes.clear # clear out the shapes for next pass
      
      # When a force or torque is set on a Body, it is cumulative
      # This means that the force you applied last SUBSTEP will compound with the
      # force applied this SUBSTEP; which is probably not the behavior you want
      # We reset the forces on the Player each SUBSTEP for this reason
      @players.each do |p|
        p.shape.body.reset_forces
      
        # If our rotation gets crazy-high, slow it down
        # Otherwise allow the player to adjust it
        if p.shape.body.w > 1.0
          p.turn_left
        elsif p.shape.body.w < -1.0
          p.turn_right
        end
      end
      
      # Perform the step over @dt period of time
      # For best performance @dt should remain consistent for the game
      $space.step(@dt)
    end
    
    # Each update (not SUBSTEP) we see if we need to add more Stars
    if rand(100) < 4 and @stars.size < 25 then
      body = CP::Body.new(0.0001, 0.0001)
      shape = CP::Shape::Circle.new(body, 25/2, CP::Vec2.new(0.0, 0.0))
      shape.collision_type = :star

      shape.e = 0.99 # elasticity
      
      $space.add_body(body)
      $space.add_shape(shape)
      
      @stars.push(Star.new(@star_anim, shape))
    end
  end
end

server = Rev::TCPServer.new(HOSTNAME, PORT, PlayerConnection)
server.attach(Rev::Loop.default)

game = Game.new

puts "Rev server listening on #{HOSTNAME}:#{PORT}"
Rev::Loop.default.run
