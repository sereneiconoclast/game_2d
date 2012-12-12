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
    handshake_response = hash['you_are']
    if handshake_response
      @game.create_local_player handshake_response
    end

    stars = hash['add_stars']
    @game.add_stars(stars) if stars

    players = hash['add_players']
    @game.add_players(players) if players

    players = hash['delete_players']
    @game.delete_players(players) if players

    registry = hash['registry']
    @game.sync_registry(registry) if registry
  end

  def send_move(move)
    send_record(:move => move.to_s) if move
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

    @players = Array.new
    @stars = Array.new

    @registry = {}

    # Here we define what is supposed to happen when a Player (ship) collides with a Star
    # I create a @remove_objects array because we cannot remove either Shapes or Bodies
    # from Space within a collision closure, rather, we have to wait till the closure
    # is through executing, then we can remove the Shapes and Bodies
    # In this case, the Shapes and the Bodies they own are removed in the Gosu::Window.update phase
    # by iterating over the @remove_objects array
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @remove_objects = []
    @space.add_collision_func(:ship, :star) do |ship_shape, star_shape|
      star = star_shape.body.object
      unless @remove_objects.include? star # filter out duplicate collisions
        @score += 10
        @beep.play
        @remove_objects << star
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

  def create_local_player(json)
    raise "Already have player #{@player}!?" if @player
    @player = add_player(json, LocalPlayer, @conn)
    puts "I am player #{@player.registry_id}"
  end

  def add_player(json, clazz=ClientPlayer, conn=nil)
    player = clazz.new(conn, json['player_name'], self)
    player.registry_id = registry_id = json['registry_id']
    puts "Added player #{player}"
    player.update_from_json(json)
    @registry[registry_id] = player
    @space.add_body(player.body)
    @space.add_shape(player.shape)
    @players << player
    player
  end

  def delete_player(player)
    return unless player
    raise "We've been kicked!!" if player == @player
    puts "Disconnected: #{player}"
    @registry.delete player.registry_id
    @players.delete player
    @space.remove_body(player.body)
    @space.remove_shape(player.shape)
  end

  def set_camera_position
    @camera_x = [[@player.body.p.x - SCREEN_WIDTH/2, 0].max, WORLD_WIDTH - SCREEN_WIDTH].min
    @camera_y = [[@player.body.p.y - SCREEN_HEIGHT/2, 0].max, WORLD_HEIGHT - SCREEN_HEIGHT].min
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
      @remove_objects.each do |object|
        # We may have just removed this object after a registry update
        next unless @registry.delete object.registry_id

        @players.delete object if object.is_a? Player
        @stars.delete object if object.is_a? Star

        @space.remove_body(object.body)
        @space.remove_shape(object.shape)
      end
      @remove_objects.clear # clear out the stars/players for next pass

      # Player at the keyboard queues up a command
      @player.handle_input if @player

      # Process commands by all players
      # For the local player, also sends command to server
      @players.each &:dequeue_move

      # Perform the step over @dt period of time
      # For best performance @dt should remain consistent for the game
      @space.step(@dt)
    end
  end

  def add_star(json)
    x, y = json['position']
    x_vel, y_vel = json['velocity']
    star = ClientStar.new(x, y, x_vel, y_vel)
    star.registry_id = registry_id = json['registry_id']
    @space.add_body(star.body)
    @space.add_shape(star.shape)

    @stars << star
    @registry[registry_id] = star
    puts "Added #{star}"
  end

  def add_stars(star_array)
    #puts "Adding #{star_array.size} stars"
    star_array.each {|json| add_star(json) }
  end

  def add_players(players)
    players.each {|json| add_player(json) }
  end

  def delete_players(players)
    players.each {|reg_id| delete_player(@registry[reg_id]) }
  end

  def draw
    @background_image.draw(0, 0, ZOrder::Background)
    return unless @player
    set_camera_position
    translate(-@camera_x, -@camera_y) do
      (@players + @stars).each &:draw
    end
    @font.draw("Score: #{@score}", 10, 10, ZOrder::UI, 1.0, 1.0, 0xffffff00)
  end

  def button_down(id)
    if id == Gosu::KbEscape
      close
    end
  end

  def sync_registry(server_registry)
    my_keys = @registry.keys

    server_registry.each do |registry_id, json|
      my_obj = @registry[registry_id]
      if my_obj
        my_obj.update_from_json(json)
      else
        clazz = json['class']
        puts "Don't have #{clazz} #{registry_id}, adding it"
        case clazz
        when 'Star' then add_star(json)
        when 'Player' then add_player(json)
        else raise "Unsupported class #{clazz}"
        end
      end

      my_keys.delete registry_id
    end

    my_keys.each do |registry_id|
      puts "Server doesn't have #{registry_id}, deleting it"
      @remove_objects << @registry[registry_id]
    end
  end
end

player_name = ARGV.shift
raise "No player name given" unless player_name
window = GameWindow.new player_name
window.show
