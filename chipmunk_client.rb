## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'trollop'
require 'gosu'

$LOAD_PATH << '.'
require 'client_connection'
require 'game_space'
require 'player'
require 'npc'
require 'menu'
require 'zorder'

SCREEN_WIDTH = 640  # in pixels
SCREEN_HEIGHT = 480 # in pixels

DEFAULT_PORT = 4321

# The Gosu::Window is always the "environment" of our game
# It also provides the pulse of our game
class GameWindow < Gosu::Window
  attr_reader :animation, :font

  def initialize(player_name, hostname, port=DEFAULT_PORT)
    super(SCREEN_WIDTH, SCREEN_HEIGHT, false, 16)
    self.caption = "Gosu/Chipmunk/ENet Integration Demo"

    @background_image = Gosu::Image.new(self, "media/Space.png", true)
    @animation = Hash.new do |h, k|
      h[k] = Gosu::Image::load_tiles(self, k, 40, 40, false)
    end

    @cursor_anim = @animation["media/crosshair.gif"]

    # Put the beep here, as it is the environment now that determines collision
    @beep = Gosu::Sample.new(self, "media/Beep.wav")

    @font = Gosu::Font.new(self, Gosu::default_font_name, 20)

    # Local settings
    @local = {
      :create_npc => {
        :snap => false,
      },
    }
    snap_text = lambda do |item|
      @local[:create_npc][:snap] ? "Turn snap off" : "Turn snap on"
    end

    submenu = Menu.new('Main menu', self, @font,
      MenuItem.new(snap_text, self, @font) do |item|
        @local[:create_npc][:snap] = !@local[:create_npc][:snap]
      end,
      MenuItem.new('Save!', self, @font) do |item|
        @conn.send_save
      end
    )
    main_menu = Menu.new('Main menu', self, @font,
      MenuItem.new('Object creation', self, @font) { submenu },
      MenuItem.new('Quit!', self, @font) { shutdown }
    )
    @menu = @top_menu = MenuItem.new('Click for menu', self, @font) { main_menu }

    # Connect to server and kick off handshaking
    # We will create our player object only after we've been accepted by the server
    # and told our starting position
    @conn = ClientConnection.new(hostname, port, self, player_name)

    @last_update = Time.now.to_r
  end

  def establish_world(world)
    @space = GameSpace.new.establish_world(
      world['cell_width'], world['cell_height'])

    # No action for fire_object_not_found
    # We may remove an object during a registry update that we were about to doom
  end

  def create_local_player(json)
    raise "Already have player #{@player}!?" if @player
    @player = add_player(json, LocalPlayer, @conn)
    puts "I am player #{@player.registry_id}"
  end

  def add_player(json, clazz=Player, conn=nil)
    player = clazz.new(@space, conn, json['player_name'], self)
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
    @space.purge_doomed_entities
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
    return unless @conn.online? && @space

    # Player at the keyboard queues up a command
    @player.handle_input if @player

    @space.update
  end

  def add_npc(json)
    json['class'] = 'NPC'
    @space << Entity.from_json(@space, json)
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
    @camera_x, @camera_y = @space.good_camera_position_for(@player, SCREEN_WIDTH, SCREEN_HEIGHT)
    translate(-@camera_x, -@camera_y) do
      (@space.players + @space.npcs).each {|entity| entity.draw(self) }
    end

    @space.players.sort.each_with_index do |player, num|
      @font.draw("#{player.player_name}: #{player.score}", 10, 10 * (num * 2 + 1), ZOrder::Text, 1.0, 1.0, Gosu::Color::YELLOW)
    end

    @menu.draw

    cursor_img = @cursor_anim[Gosu::milliseconds / 50 % @cursor_anim.size]
    cursor_img.draw(
      mouse_x - cursor_img.width / 2.0,
      mouse_y - cursor_img.height / 2.0,
      ZOrder::Cursor,
      1, 1, Gosu::Color::WHITE, :add)
  end

  def draw_box_at(x1, y1, x2, y2, c)
    draw_quad(x1, y1, c, x2, y1, c, x2, y2, c, x1, y2, c, ZOrder::Highlight)
  end

  def button_down(id)
    case id
      when Gosu::KbEscape then @menu = @top_menu
      when Gosu::MsLeft then
        if new_menu = @menu.handle_click
          @menu = (new_menu.respond_to?(:handle_click) ? new_menu : @top_menu)
        else
          create_npc
        end
    end
  end

  def create_npc
    # For some reason, Gosu's mouse_x/mouse_y return Floats, so round it off
    mx, my = mouse_x.round, mouse_y.round
    pixel_x, pixel_y = (mx + @camera_x), (my + @camera_y)
#   puts "Mouse click on pixel #{mx}x#{my}, camera-adjusted to #{pixel_x}x#{pixel_y}"
    x, y = pixel_x * Entity::PIXEL_WIDTH, pixel_y * Entity::PIXEL_WIDTH
#   puts "Raw X/Y position of click is #{x}x#{y}"

    if @local[:create_npc][:snap]
      # When snap is on, we want the upper-left corner of the cell we clicked in
      x = (x / Entity::WIDTH) * Entity::WIDTH
      y = (y / Entity::HEIGHT) * Entity::HEIGHT
#     puts "Snapped X/Y position is #{x}x#{y}"
    else
      # When snap is off, we want the click to be the new entity's center, not
      # its upper-left corner
      x -= Entity::WIDTH / 2
      y -= Entity::HEIGHT / 2
#     puts "Adjusted un-snapped X/Y position is #{x}x#{y}"
    end

    @conn.send_create_npc(:x => x, :y => y)
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
