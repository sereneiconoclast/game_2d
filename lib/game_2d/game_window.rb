## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'facets/kernel/try'
require 'rubygems'
require 'gosu'

require 'game_2d/client_connection'
require 'game_2d/client_engine'
require 'game_2d/game_space'
require 'game_2d/entity'
require 'game_2d/player'
require 'game_2d/menu'
require 'game_2d/message'
require 'game_2d/password_dialog'
require 'game_2d/zorder'

SCREEN_WIDTH = 640  # in pixels
SCREEN_HEIGHT = 480 # in pixels

DEFAULT_PORT = 4321
DEFAULT_KEY_SIZE = 1024

# The Gosu::Window is always the "environment" of our game
# It also provides the pulse of our game
class GameWindow < Gosu::Window
  attr_reader :animation, :font, :top_menu
  attr_accessor :player_id

  def initialize(opts = {})
    player_name = opts[:name]
    hostname = opts[:hostname]
    port = opts[:port] || DEFAULT_PORT
    key_size = opts[:key_size] || DEFAULT_KEY_SIZE
    profile = opts[:profile] || false

    @conn_update_total = @engine_update_total = 0.0
    @conn_update_count = @engine_update_count = 0
    @profile = profile

    super(SCREEN_WIDTH, SCREEN_HEIGHT, false, 16)
    self.caption = "Game 2D"

    @pressed_buttons = []

    @background_image = Gosu::Image.new(self, media("Space.png"), true)
    @animation = Hash.new do |h, k|
      h[k] = Gosu::Image::load_tiles(
        self, k, Entity::CELL_WIDTH_IN_PIXELS, Entity::CELL_WIDTH_IN_PIXELS, false)
    end

    @cursor_anim = @animation[media("crosshair.gif")]

    @beep = Gosu::Sample.new(self, media("Beep.wav")) # not used yet

    @font = Gosu::Font.new(self, Gosu::default_font_name, 20)

    # Local settings
    @local = {
      :create_npc => {
        :type => 'Entity::Block',
        :hp   => 5,
        :snap => false,
      },
    }

    @run_start = Time.now.to_f
    @update_count = 0

    @conn = ClientConnection.new(hostname, port, self, player_name, key_size)
    @engine = @conn.engine = ClientEngine.new(self)
    @menu = build_top_menu
    @dialog = PasswordDialog.new(self, @font)
  end

  def display_message(*lines)
    if @message
      @message.lines = lines
    else
      @message = Message.new(self, @font, lines)
    end
  end

  def message_drawn?; @message.try(:drawn?); end

  # Ensure the message is drawn at least once
  def display_message!(*lines)
    display_message(*lines)
    sleep 0.01 until message_drawn?
  end

  def clear_message
    @message = nil
  end

  def build_top_menu
    @top_menu = MenuItem.new('Click for menu', self, @font) { main_menu }
  end

  def main_menu
    Menu.new('Main menu', self, @font,
      MenuItem.new('Object creation', self, @font) { object_creation_menu },
      MenuItem.new('Quit!', self, @font) { shutdown }
    )
  end

  def object_creation_menu
    snap_text = lambda do |item|
      @local[:create_npc][:snap] ? "Turn snap off" : "Turn snap on"
    end

    Menu.new('Object creation', self, @font,
      MenuItem.new('Object type', self, @font) { object_type_menu },
      MenuItem.new(snap_text, self, @font) do
        @local[:create_npc][:snap] = !@local[:create_npc][:snap]
      end,
      MenuItem.new('Save!', self, @font) { @conn.send_save }
    )
  end

  def object_type_menu
    Menu.new('Object type', self, @font, *object_type_submenus)
  end

  def object_type_submenus
    [
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
  end

  def media(filename)
    "#{File.dirname __FILE__}/../../media/#{filename}"
  end

  def space
    @engine.space
  end

  def player
    space[@player_id]
  end

  def update
    @update_count += 1

    return unless @conn.online?

    # Handle any pending ENet events
    before_t = Time.now.to_f
    @conn.update
    if @profile
      @conn_update_total += (Time.now.to_f - before_t)
      @conn_update_count += 1
      $stderr.puts "@conn.update() averages #{@conn_update_total / @conn_update_count} seconds each" if (@conn_update_count % 60) == 0
    end
    return unless @engine.world_established?

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
    @dialog.draw if @dialog
    @message.draw if @message
    @menu.draw if @menu

    cursor_img = @cursor_anim[Gosu::milliseconds / 50 % @cursor_anim.size]
    cursor_img.draw(
      mouse_x - cursor_img.width / 2.0,
      mouse_y - cursor_img.height / 2.0,
      ZOrder::Cursor,
      1, 1, Gosu::Color::WHITE, :add)

    return unless @player_id

    @camera_x, @camera_y = space.good_camera_position_for(player, SCREEN_WIDTH, SCREEN_HEIGHT)
    translate(-@camera_x, -@camera_y) do
      (space.players + space.npcs).each {|entity| entity.draw(self) }
    end

    space.players.sort.each_with_index do |player, num|
      @font.draw("#{player.player_name}: #{player.score}", 10, 10 * (num * 2 + 1), ZOrder::Text, 1.0, 1.0, Gosu::Color::YELLOW)
    end
  end

  def draw_box_at(x1, y1, x2, y2, c)
    draw_quad(x1, y1, c, x2, y1, c, x2, y2, c, x1, y2, c, ZOrder::Highlight)
  end

  def button_down(id)
    case id
      when Gosu::KbEnter, Gosu::KbReturn then
        if @dialog
          @dialog.enter
          @conn.start(@dialog.password_hash)
          @dialog = nil
        end
      when Gosu::KbP then
        @conn.send_ping unless @dialog
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
      else @pressed_buttons << id unless @dialog
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
  #
  def move_for_keypress
    # Generated once for each keypress
    until @pressed_buttons.empty?
      button = @pressed_buttons.shift
      case button
        when Gosu::KbUp, Gosu::KbW
          return (player.building?) ? :rise_up : :flip
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
        :build
    end
  end
end
