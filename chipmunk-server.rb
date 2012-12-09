## File: ChipmunkIntegration.rb
## Author: Dirk Johnson
## Version: 1.0.0
## Date: 2007-10-05
## License: Same as for Gosu (MIT)
## Comments: Based on the Gosu Ruby Tutorial, but incorporating the Chipmunk Physics Engine
## See https://github.com/jlnr/gosu/wiki/Ruby-Chipmunk-Integration for the accompanying text.

require 'rubygems'
require 'gosu'
require 'chipmunk'

$LOAD_PATH << '.'
require 'networking'
require 'player'
require 'star'

WORLD_WIDTH = 900
WORLD_HEIGHT = 600

HOSTNAME = 'localhost'
PORT = 4321

# The number of steps to process every Gosu update
# The Player ship can get going so fast as to "move through" a
# star without triggering a collision; an increased number of
# Chipmunk step calls per update will effectively avoid this issue
$SUBSTEPS = 6

class PlayerConnection < Networking

  def setup(game)
    puts "#{object_id} -- #{remote_addr}:#{remote_port} connected"
    @game = game
  end

  def answer_handshake(handshake)
    player_name = handshake['player_name']
    @player = @game.add_player(self, player_name)

    response = {
      'player_vector' => [ @player.body.p.x, @player.body.p.y, @player.body.v.x, @player.body.v.y ],
      'add_stars' => @game.get_all_star_vectors
    }
    puts "Answering handshake from #{player_name}: #{response.inspect}"
    send_record response
  end

  def on_close
    puts "#{object_id} -- #{remote_addr}:#{remote_port} disconnected"
  end

  def on_read(data)
    if (handshake = data['handshake'])
      answer_handshake(handshake)
    else
      puts "TODO TODO TODO..."
    end
  end
end

# Convenience method for converting from radians to a Vec2 vector.
class Numeric
  def radians_to_vec2
    CP::Vec2.new(Math::cos(self), Math::sin(self))
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

  def add_player(player_name, conn)
    player = Player.new(conn, player_name)
    $space.add_body(player.body)
    $space.add_shape(player.shape)
    x, y = WORLD_WIDTH / 2, WORLD_HEIGHT / 2 # start in the center of the world
    player.warp(x, y)
    @players << player
    player
  end

  def get_all_star_vectors
    @stars.collect {|s| [s.body.p.x, s.body.p.y, s.body.v.x, s.body.v.y] }
  end

  def on_timer
    # Step the physics environment $SUBSTEPS times each update
    $SUBSTEPS.times do
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
      star = Star.new(rand * WORLD_WIDTH, rand * WORLD_HEIGHT)
      $space.add_body(star.body)
      $space.add_shape(star.shape)
      @stars << star
    end
  end
end

game = Game.new

server = Rev::TCPServer.new(HOSTNAME, PORT, PlayerConnection) {|conn| conn.setup(game) }
server.attach(Rev::Loop.default)

puts "Rev server listening on #{HOSTNAME}:#{PORT}"
Rev::Loop.default.run
