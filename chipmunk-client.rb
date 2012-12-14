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
require 'client_connection'
require 'game_space'
require 'player'
require 'star'
require 'zorder'

SCREEN_WIDTH = 640
SCREEN_HEIGHT = 480

HOSTNAME = 'localhost'
PORT = 4321

# The number of steps to process every Gosu update
# The Player ship can get going so fast as to "move through" a
# star without triggering a collision; an increased number of
# Chipmunk step calls per update will effectively avoid this issue
# TODO: Get from server
$SUBSTEPS = 6


# The Gosu::Window is always the "environment" of our game
# It also provides the pulse of our game
class GameWindow < Gosu::Window
  def initialize(player_name)
    super(SCREEN_WIDTH, SCREEN_HEIGHT, false, 16)
    self.caption = "Gosu/Chipmunk/Rev Integration Demo"

    @background_image = Gosu::Image.new(self, "media/Space.png", true)

    # Load star animation using window
    ClientStar.load_animation(self)

    # Put the beep here, as it is the environment now that determines collision
    @beep = Gosu::Sample.new(self, "media/Beep.wav")

    @font = Gosu::Font.new(self, Gosu::default_font_name, 20)

    @space = GameSpace.new(1.0/60.0) # TODO: Get from server

    # No action for fire_object_not_found
    # We may remove an object during a registry update that we were about to doom

    # Here we define what is supposed to happen when a Player (ship) collides with a Star
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @space.add_collision_func(:ship, :star) do |ship_shape, star_shape|
      star = star_shape.body.object
      unless @space.doomed? star # filter out duplicate collisions
        @beep.play
        @space.doom star
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

  def establish_world(width, height)
    @space.establish_world(width, height)
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
    @space << player
  end

  def delete_player(player)
    return unless player
    raise "We've been kicked!!" if player == @player
    puts "Disconnected: #{player}"
    @space.doom player
    @space.purge_doomed_objects
  end

  def update
    # Handle any pending Rev events
    Rev::Loop.default.run_nonblock

    # Step the physics environment $SUBSTEPS times each update
    $SUBSTEPS.times do

      # Player at the keyboard queues up a command
      @player.handle_input if @player

      @space.update
    end
  end

  def add_star(json)
    x, y = json['position']
    x_vel, y_vel = json['velocity']
    star = ClientStar.new(x, y, x_vel, y_vel)
    star.registry_id = json['registry_id']
    @space << star
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
    players.each {|reg_id| delete_player(@space[reg_id]) }
  end

  def update_score(update)
    registry_id, score = update.to_a.first
    return unless player = @space[registry_id]
    player.score = score
  end

  def draw
    @background_image.draw(0, 0, ZOrder::Background)
    return unless @player
    camera_x, camera_y = @space.good_camera_position_for(@player, SCREEN_WIDTH, SCREEN_HEIGHT)
    translate(-camera_x, -camera_y) do
      (@space.players + @space.stars).each &:draw
    end

    @space.players.sort.each_with_index do |player, num|
      @font.draw("#{player.player_name}: #{player.score}", 10, 10 * (num * 2 + 1), ZOrder::UI, 1.0, 1.0, 0xffffff00)
    end
  end

  def button_down(id)
    if id == Gosu::KbEscape
      close
    end
  end

  def sync_registry(server_registry)
    registry = @space.registry
    my_keys = registry.keys

    server_registry.each do |registry_id, json|
      my_obj = registry[registry_id]
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
      @space.doom @space[registry_id]
    end
  end
end

player_name = ARGV.shift
raise "No player name given" unless player_name
window = GameWindow.new player_name
window.show
