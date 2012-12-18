## File: ChipmunkIntegration.rb
## Author: Dirk Johnson
## Version: 1.0.0
## Date: 2007-10-05
## License: Same as for Gosu (MIT)
## Comments: Based on the Gosu Ruby Tutorial, but incorporating the Chipmunk Physics Engine
## See https://github.com/jlnr/gosu/wiki/Ruby-Chipmunk-Integration for the accompanying text.

require 'rubygems'
require 'trollop'
require 'gosu'

$LOAD_PATH << '.'
require 'chipmunk_utilities'
require 'client_connection'
require 'game_space'
require 'player'
require 'npc'
require 'zorder'

SCREEN_WIDTH = 640
SCREEN_HEIGHT = 480

DEFAULT_PORT = 4321

$SUBSTEPS = 0

# The Gosu::Window is always the "environment" of our game
# It also provides the pulse of our game
class GameWindow < Gosu::Window
  def initialize(player_name, hostname, port=DEFAULT_PORT)
    super(SCREEN_WIDTH, SCREEN_HEIGHT, false, 16)
    self.caption = "Gosu/Chipmunk/ENet Integration Demo"

    @background_image = Gosu::Image.new(self, "media/Space.png", true)

    # Load NPC animation using window
    ClientNPC.load_animation(self)

    # Put the beep here, as it is the environment now that determines collision
    @beep = Gosu::Sample.new(self, "media/Beep.wav")

    @font = Gosu::Font.new(self, Gosu::default_font_name, 20)

    # Connect to server and kick off handshaking
    # We will create our player object only after we've been accepted by the server
    # and told our starting position
    @conn = ClientConnection.new(hostname, port, self, player_name)

    @last_update = Time.now.to_r
  end

  def establish_world(world)
    @space = GameSpace.new(world['delta_t'])

    # No action for fire_object_not_found
    # We may remove an object during a registry update that we were about to doom

    @space.establish_world(world['width'], world['height'])

    # Here we define what is supposed to happen when a Player (ship) collides with an NPC
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @space.add_collision_func(:ship, :npc) do |ship_shape, npc_shape|
      npc = npc_shape.body.object
      unless @space.doomed? npc # filter out duplicate collisions
        @beep.play
        @space.doom npc
        # remember to return 'true' if we want regular collision handling
      end
    end

    # The number of steps to process every Gosu update
    #
    # Until this is set, update() does nothing.  So we set this last
    $SUBSTEPS = world['substeps']
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
    # Gosu calls update() every 16 ms.  This results in about 62 updates per second.
    # We need to get this as close to 60 updates per second as possible.
    # Otherwise the client will run ahead of the server, sending too many
    # commands, which queue up on the server side and cause the two to fall badly
    # out of sync.
    sleeping = (@last_update + Rational(1, 60)) - Time.now.to_r
    sleep(sleeping) if sleeping > 0.0

    # Record the time -after- the sleep
    @last_update = Time.now.to_r

    # Handle any pending ENet events
    @conn.update(0) # non-blocking
    return unless @conn.online?

    # Player at the keyboard queues up a command
    @player.handle_input if @player

    # All players dequeue moves
    @space.dequeue_player_moves

    # Step the physics environment $SUBSTEPS times each update
    $SUBSTEPS.times do
      @space.update
      @conn.update(0)
    end
  end

  def add_npc(json)
    x, y = json['position']
    x_vel, y_vel = json['velocity']
    npc = ClientNPC.new(x, y, x_vel, y_vel)
    npc.registry_id = json['registry_id']
    @space << npc
    # puts "Added #{npc}"
  end

  def add_npcs(npc_array)
    npc_array.each {|json| add_npc(json) }
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
      (@space.players + @space.npcs).each &:draw

      @space.players.each do |player|
        @font.draw_rel(player.player_name, player.body.p.x, player.body.p.y - 30, ZOrder::UI, 0.5, 0.5, 1.0, 1.0, 0xffffff00)
      end
    end

    @space.players.sort.each_with_index do |player, num|
      @font.draw("#{player.player_name}: #{player.score}", 10, 10 * (num * 2 + 1), ZOrder::UI, 1.0, 1.0, 0xffffff00)
    end
  end

  def button_down(id)
    if id == Gosu::KbEscape
      shutdown
    end
  end

  def shutdown
    @conn.disconnect(200)
    close
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
        when 'NPC' then add_npc(json)
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

opts = Trollop::options do
  opt :name, "Player name", :type => :string, :required => true
  opt :hostname, "Hostname of server", :type => :string, :required => true
  opt :port, "Port number", :default => DEFAULT_PORT
end

window = GameWindow.new( opts[:name], opts[:hostname], opts[:port] )
window.show
