## File: ChipmunkIntegration.rb
## Author: Dirk Johnson
## Version: 1.0.0
## Date: 2007-10-05
## License: Same as for Gosu (MIT)
## Comments: Based on the Gosu Ruby Tutorial, but incorporating the Chipmunk Physics Engine
## See https://github.com/jlnr/gosu/wiki/Ruby-Chipmunk-Integration for the accompanying text.

require 'rubygems'
require 'gosu'

$LOAD_PATH << '.'
require 'chipmunk_utilities'
require 'networking'
require 'player'
require 'star'
require 'zorder'

SCREEN_WIDTH = 640
SCREEN_HEIGHT = 480
WORLD_WIDTH = 900
WORLD_HEIGHT = 600

HOSTNAME = 'localhost'
PORT = 4321

# The number of steps to process every Gosu update
# The Player ship can get going so fast as to "move through" a
# star without triggering a collision; an increased number of
# Chipmunk step calls per update will effectively avoid this issue
$SUBSTEPS = 6

class ClientConnection < Networking
  attr_reader :player_name

  def self.connect(host, port, *args)
    super
  end

  def setup(game, player_name)
    @game = game
    @player_name = player_name
    self
  end

  def on_connect
    super
    puts "Connected to server #{remote_addr}:#{remote_port}; sending handshake"
    send_record :handshake => { :player_name => @player_name }
  end

  def on_close
    puts "Client disconnected"
    @game.close
  end

  def on_record(hash)
    player_id = hash['player_id']
    @game.create_player(player_id) if player_id
    player_vector = hash['player_vector']
    @game.set_player_vector(*player_vector) if player_vector

    stars = hash['add_stars']
    @game.add_stars(stars) if stars
  end
end

# The Gosu::Window is always the "environment" of our game
# It also provides the pulse of our game
class GameWindow < Gosu::Window

  def initialize(player_name)
    super(SCREEN_WIDTH, SCREEN_HEIGHT, false, 16)
    self.caption = "Gosu & Chipmunk Integration Demo"
    @background_image = Gosu::Image.new(self, "media/Space.png", true)

    # Load star animation using window
    ClientStar.load_animation(self)

    # Put the beep here, as it is the environment now that determines collision
    @beep = Gosu::Sample.new(self, "media/Beep.wav")

    # Put the score here, as it is the environment that tracks this now
    @score = 0
    @font = Gosu::Font.new(self, Gosu::default_font_name, 20)

    # Time increment over which to apply a physics "step" ("delta t")
    @dt = (1.0/60.0)

    # Create our Space and set its damping
    # A damping of 0.8 causes the ship bleed off its force and torque over time
    # This is not realistic behavior in a vacuum of space, but it gives the game
    # the feel I'd like in this situation
    @space = CP::Space.new
    # @space.damping = 0.8
    @space.gravity = CP::Vec2.new(0.0, 10.0)

    # Walls all around the screen
    add_bounding_wall(WORLD_WIDTH / 2, 0.0, WORLD_WIDTH, 0.0)   # top
    add_bounding_wall(WORLD_WIDTH / 2, WORLD_HEIGHT, WORLD_WIDTH, 0.0) # bottom
    add_bounding_wall(0.0, WORLD_HEIGHT / 2, 0.0, WORLD_HEIGHT)   # left
    add_bounding_wall(WORLD_WIDTH, WORLD_HEIGHT / 2, 0.0, WORLD_HEIGHT) # right

    @stars = Array.new

    @registry = {}

    # Here we define what is supposed to happen when a Player (ship) collides with a Star
    # I create a @remove_shapes array because we cannot remove either Shapes or Bodies
    # from Space within a collision closure, rather, we have to wait till the closure
    # is through executing, then we can remove the Shapes and Bodies
    # In this case, the Shapes and the Bodies they own are removed in the Gosu::Window.update phase
    # by iterating over the @remove_shapes array
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @remove_shapes = []
    @space.add_collision_func(:ship, :star) do |ship_shape, star_shape|
      unless @remove_shapes.include? star_shape # filter out duplicate collisions
        @score += 10
        @beep.play
        @remove_shapes << star_shape
        # remember to return 'true' if we want regular collision handling
      end
    end

    # Connect to server and kick off handshaking
    # We will create our player object only after we've been accepted by the server
    # and told our starting position
    @conn = connect_to_server HOSTNAME, PORT, player_name
  end

  def connect_to_server(hostname, port, player_name)
    conn = ClientConnection.connect(hostname, port)
    conn.attach(Rev::Loop.default)
    conn.setup(self, player_name)
  end

  def create_player(registry_id)
    raise "Already have player #{@player}!?" if @player
    @player = ClientPlayer.new(@conn, @conn.player_name, self)
    @player.registry_id = registry_id
    @registry[registry_id] = @player
    @space.add_body(@player.body)
    @space.add_shape(@player.shape)
  end

  def set_player_vector(x, y, vel_x, vel_y)
    raise "No player!?" unless @player
    @player.warp(x, y, vel_x, vel_y)
  end

  def set_camera_position
    @camera_x = [[@player.shape.body.p.x - SCREEN_WIDTH/2, 0].max, WORLD_WIDTH - SCREEN_WIDTH].min
    @camera_y = [[@player.shape.body.p.y - SCREEN_HEIGHT/2, 0].max, WORLD_HEIGHT - SCREEN_HEIGHT].min
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
    @space.add_body(wall)
    @space.add_shape(shape)
  end

  def update
    # Handle any pending Rev events
    Rev::Loop.default.run_nonblock

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
        @space.remove_body(shape.body)
        @space.remove_shape(shape)
      end
      @remove_shapes.clear # clear out the shapes for next pass

      if @player
        # When a force or torque is set on a Body, it is cumulative
        # This means that the force you applied last SUBSTEP will compound with the
        # force applied this SUBSTEP; which is probably not the behavior you want
        # We reset the forces on the Player each SUBSTEP for this reason
        @player.shape.body.reset_forces

        # If our rotation gets crazy-high, slow it down
        # Otherwise allow the player to adjust it
        if @player.shape.body.w > 1.0
          @player.turn_left
        elsif @player.shape.body.w < -1.0
          @player.turn_right
        # Check keyboard
        elsif button_down? Gosu::KbLeft
          @player.turn_left
        elsif button_down? Gosu::KbRight
          @player.turn_right
        end

        if button_down? Gosu::KbUp
          if ( (button_down? Gosu::KbRightShift) || (button_down? Gosu::KbLeftShift) )
            @player.boost
          else
            @player.accelerate
          end
        elsif button_down? Gosu::KbDown
          @player.reverse
        end
      end

      # Perform the step over @dt period of time
      # For best performance @dt should remain consistent for the game
      @space.step(@dt)
    end
  end

  def add_star(registry_id, x, y, x_vel, y_vel)
    star = ClientStar.new(x, y, x_vel, y_vel)
    star.registry_id = registry_id
    @space.add_body(star.body)
    @space.add_shape(star.shape)

    @stars << star
    puts "Added #{star}"
  end

  def add_stars(star_array)
    #puts "Adding #{star_array.size} stars"
    star_array.each {|args| add_star(*args) }
  end

  def draw
    @background_image.draw(0, 0, ZOrder::Background)
    return unless @player
    set_camera_position
    translate(-@camera_x, -@camera_y) do
      @player.draw
      @stars.each &:draw
    end
    @font.draw("Score: #{@score}", 10, 10, ZOrder::UI, 1.0, 1.0, 0xffffff00)
  end

  def button_down(id)
    if id == Gosu::KbEscape
      close
    end
  end
end

player_name = ARGV.shift
raise "No player name given" unless player_name
window = GameWindow.new player_name
window.show
