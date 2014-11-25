## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'trollop'
require 'gosu'

$LOAD_PATH << '.'
require 'client_connection'
require 'client_engine'
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
  attr_accessor :player_id

  def initialize(player_name, hostname, port=DEFAULT_PORT, profile=false)
    @conn_update_total = @engine_update_total = 0.0
    @conn_update_count = @engine_update_count = 0
    @profile = profile

    super(SCREEN_WIDTH, SCREEN_HEIGHT, false, 16)
    self.caption = "Ruby Gosu Game"

    @pressed_buttons = []

    @background_image = Gosu::Image.new(self, "media/Space.png", true)
    @animation = Hash.new do |h, k|
      h[k] = Gosu::Image::load_tiles(
        self, k, Entity::CELL_WIDTH_IN_PIXELS, Entity::CELL_WIDTH_IN_PIXELS, false)
    end

    @cursor_anim = @animation["media/crosshair.gif"]

    # Put the beep here, as it is the environment now that determines collision
    @beep = Gosu::Sample.new(self, "media/Beep.wav")

    @font = Gosu::Font.new(self, Gosu::default_font_name, 20)

    # Local settings
    @local = {
      :create_npc => {
        :type => 'Entity::Block',
        :hp   => 5,
        :snap => false,
      },
    }
    snap_text = lambda do |item|
      @local[:create_npc][:snap] ? "Turn snap off" : "Turn snap on"
    end

    object_type_submenus = [
      ['Dirt',       'Entity::Block',    5],
      ['Brick',      'Entity::Block',    10],
      ['Cement',     'Entity::Block',    15],
      ['Steel',      'Entity::Block',    20],
      ['Unlikelium', 'Entity::Block',    25],
      ['Titanium',   'Entity::Titanium', 0]
    ].collect do |type_name, class_name, hp|
      MenuItem.new(type_name, self, @font) do |item|
        @local[:create_npc][:type] = class_name
        @local[:create_npc][:hp] = hp
      end
    end
    object_type_menu = Menu.new('Object type', self, @font,
      *object_type_submenus)

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
    @engine = @conn.engine = ClientEngine.new(self)
    @run_start = Time.now.to_f
    @update_count = 0
  end

  def space
    @engine.space
  end

  def player
    space[@player_id]
  end

  def update
    @update_count += 1

    # Handle any pending ENet events
    before_t = Time.now.to_f
    @conn.update
    if @profile
      @conn_update_total += (Time.now.to_f - before_t)
      @conn_update_count += 1
      $stderr.puts "@conn.update() averages #{@conn_update_total / @conn_update_count} seconds each" if (@conn_update_count % 60) == 0
    end
    return unless @conn.online? && @engine

    before_t = Time.now.to_f
    @engine.update
    if @profile
      @engine_update_total += (Time.now.to_f - before_t)
      @engine_update_count += 1
      $stderr.puts "@engine.update() averages #{@engine_update_total / @engine_update_count} seconds" if (@engine_update_count % 60) == 0
    end

    # Player at the keyboard queues up a command
    # @pressed_buttons is emptied by handle_input
    handle_input if @player_id

    $stderr.puts "Updates per second: #{@update_count / (Time.now.to_f - @run_start)}" if @profile
  end

  def draw
    @background_image.draw(0, 0, ZOrder::Background)
    return unless @player_id
    @camera_x, @camera_y = space.good_camera_position_for(player, SCREEN_WIDTH, SCREEN_HEIGHT)
    translate(-@camera_x, -@camera_y) do
      (space.players + space.npcs).each {|entity| entity.draw(self) }
    end

    space.players.sort.each_with_index do |player, num|
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
      when Gosu::KbP then @conn.send_ping
      when Gosu::KbEscape then @menu = @top_menu
      when Gosu::MsLeft then # left-click
        if new_menu = @menu.handle_click
          # If handle_click returned anything, the menu consumed the click
          # If it returned a menu, that's the new one we display
          @menu = (new_menu.respond_to?(:handle_click) ? new_menu : @top_menu)
        else
          send_fire
        end
      when Gosu::MsRight then # right-click
        send_create_npc
      else @pressed_buttons << id
    end
  end

  def send_fire
    return unless @player_id
    x, y = mouse_coords
    x_vel = (x - (player.x + Entity::WIDTH / 2)) / Entity::PIXEL_WIDTH
    y_vel = (y - (player.y + Entity::WIDTH / 2)) / Entity::PIXEL_WIDTH
    @conn.send_move :fire, :x_vel => x_vel, :y_vel => y_vel
  end

  # X/Y position of the mouse (center of the crosshairs), adjusted for camera
  def mouse_coords
    # For some reason, Gosu's mouse_x/mouse_y return Floats, so round it off
    [
      (mouse_x.round + @camera_x) * Entity::PIXEL_WIDTH,
      (mouse_y.round + @camera_y) * Entity::PIXEL_WIDTH
    ]
  end

  def send_create_npc
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
      :moving => true,
      :hp => @local[:create_npc][:hp]
    )
  end

  def shutdown
    @conn.disconnect
    close
  end

  # Dequeue an input event
  def handle_input
    return if player.falling?
    move = move_for_keypress
    @conn.send_move move # also creates a delta in the engine
  end

  # Check keyboard, return a motion symbol or nil
  #
  # Returning a symbol is only useful for actions we can
  # safely process client-side without a server round-trip.
  # Any action that creates another entity must be sent to the
  # server and processed there first, since only the server is
  # allowed to generate registry IDs.  TODO: This could possibly
  # be fixed, by assigning an ID to every move, and having the
  # server send back the ID of the move that created the object.
  # Then the client could make up a temporary ID for its idea of
  # the object, and substitute the actual ID as soon as it hears
  # what that is.
  def move_for_keypress
    # Generated once for each keypress
    until @pressed_buttons.empty?
      button = @pressed_buttons.shift
      case button
        when Gosu::KbUp, Gosu::KbW
          return (player.building?) ? :rise_up : :flip
        when Gosu::KbLeft, Gosu::KbRight, Gosu::KbA, Gosu::KbD # nothing
        else puts "Ignoring key #{button}"
      end
    end

    # Continuously-generated when key held down
    case
      when button_down?(Gosu::KbLeft), button_down?(Gosu::KbA)
        :slide_left
      when button_down?(Gosu::KbRight), button_down?(Gosu::KbD)
        :slide_right
      when button_down?(Gosu::KbRightControl), button_down?(Gosu::KbLeftControl)
        :brake
      when button_down?(Gosu::KbDown), button_down?(Gosu::KbS)
        send_build
        nil
    end
  end

  def send_build
    @conn.send_move :build
  end
end

if $PROGRAM_NAME == __FILE__
  opts = Trollop::options do
    opt :name, "Player name", :type => :string, :required => true
    opt :hostname, "Hostname of server", :type => :string, :required => true
    opt :port, "Port number", :default => DEFAULT_PORT
    opt :profile, "Turn on profiling", :type => :boolean
    opt :debug_traffic, "Debug network traffic", :type => :boolean
  end

  $debug_traffic = opts[:debug_traffic] || false

  window = GameWindow.new( opts[:name], opts[:hostname], opts[:port], opts[:profile] )
  window.show
end