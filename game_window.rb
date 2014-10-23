## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'trollop'
require 'gosu'

$LOAD_PATH << '.'
require 'client_connection'
require 'game_space'
require 'entity'
require 'player'
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

    @pressed_buttons = []

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
        :type => 'Entity::Block',
        :snap => false,
      },
    }
    snap_text = lambda do |item|
      @local[:create_npc][:snap] ? "Turn snap off" : "Turn snap on"
    end

    object_type_menu = Menu.new('Object type', self, @font,
      *(%w[Block Titanium].collect do |type_name|
        MenuItem.new(type_name, self, @font) do |item|
          @local[:create_npc][:type] = "Entity::#{type_name}"
        end
      end)
    )
    object_creation_menu = Menu.new('Object creation', self, @font,
      MenuItem.new('Object type', self, @font) { object_type_menu },
      MenuItem.new(snap_text, self, @font) do
        @local[:create_npc][:snap] = !@local[:create_npc][:snap]
      end,
      MenuItem.new('Save!', self, @font) { @conn.send_save }
    )
    main_menu = Menu.new('Main menu', self, @font,
      MenuItem.new('Object creation', self, @font) { object_creation_menu },
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
    @player = add_player(json, @conn)
    puts "I am player #{@player.registry_id}"
  end

  def add_player(json, conn=nil)
    player = Player.new(@space, conn, json['player_name'])
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

    @space.update

    # Player at the keyboard queues up a command
    # @pressed_buttons is emptied by handle_input
    @player.handle_input(self, @pressed_buttons) if @player
  end

  def add_npc(json)
    @space << Entity.from_json(@space, json)
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
      when Gosu::MsLeft then # left-click
        if new_menu = @menu.handle_click
          # If handle_click returned anything, the menu consumed the click
          # If it returned a menu, that's the new one we display
          @menu = (new_menu.respond_to?(:handle_click) ? new_menu : @top_menu)
        else
          fire
        end
      when Gosu::MsRight then # right-click
        create_npc
      else @pressed_buttons << id
    end
  end

  def fire
    return unless @player
    x, y = mouse_coords
    x_vel = (x - (@player.x + Entity::WIDTH / 2)) / Entity::PIXEL_WIDTH
    y_vel = (y - (@player.y + Entity::WIDTH / 2)) / Entity::PIXEL_WIDTH
    @player.fire x_vel, y_vel
  end

  # X/Y position of the mouse (center of the crosshairs), adjusted for camera
  def mouse_coords
    # For some reason, Gosu's mouse_x/mouse_y return Floats, so round it off
    [
      (mouse_x.round + @camera_x) * Entity::PIXEL_WIDTH,
      (mouse_y.round + @camera_y) * Entity::PIXEL_WIDTH
    ]
  end

  def create_npc
    x, y = mouse_coords

    if @local[:create_npc][:snap]
      # When snap is on, we want the upper-left corner of the cell we clicked in
      x = (x / Entity::WIDTH) * Entity::WIDTH
      y = (y / Entity::HEIGHT) * Entity::HEIGHT
    else
      # When snap is off, we want the click to be the new entity's center, not
      # its upper-left corner
      x -= Entity::WIDTH / 2
      y -= Entity::HEIGHT / 2
    end

    @conn.send_create_npc(
      :class => @local[:create_npc][:type],
      :position => [x, y],
      :velocity => [0, 0],
      :angle => 0,
      :moving => true
    )
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
        when 'Player' then add_player(json)
        else add_npc(json)
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
