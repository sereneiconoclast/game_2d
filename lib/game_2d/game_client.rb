## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'facets/kernel/try'
require 'gosu'

require 'game_2d/client_connection'
require 'game_2d/client_engine'
require 'game_2d/entity'
require 'game_2d/entity_constants'
require 'game_2d/entity/base'
require 'game_2d/entity/block'
require 'game_2d/entity/destination'
require 'game_2d/entity/gecko'
require 'game_2d/entity/hole'
require 'game_2d/entity/slime'
require 'game_2d/entity/teleporter'
require 'game_2d/entity/titanium'
require 'game_2d/game_space'
require 'game_2d/menu'
require 'game_2d/message'
require 'game_2d/password_dialog'
require 'game_2d/zorder'

# We put as many methods here as possible, so we can test them
# without instantiating an actual Gosu window
module GameClient
  # Gosu methods we call:
  # caption=(text)
  # width
  # mouse_x
  # mouse_y
  # close
  # button_down?
  # text_input=(Gosu::TextInput instance)
  # draw_quad (from draw only)
  # translate (from draw only)
  #
  # Gosu methods it calls on us:
  # draw
  # button_down

  include EntityConstants

  SCREEN_WIDTH = 640  # in pixels
  SCREEN_HEIGHT = 480 # in pixels

  DEFAULT_PORT = 4321
  DEFAULT_KEY_SIZE = 1024

  attr_reader :animation, :font, :top_menu, :player_name, :player_id

  def initialize_from_hash(opts = {})
    @player_name = opts[:name]
    hostname = opts[:hostname]
    port = opts[:port] || DEFAULT_PORT
    key_size = opts[:key_size] || DEFAULT_KEY_SIZE
    profile = opts[:profile] || false

    @conn_update_total = @engine_update_total = 0.0
    @conn_update_count = @engine_update_count = 0
    @profile = profile

    self.caption = "Game 2D - #{@player_name} on #{hostname}"

    @pressed_buttons = []

    @snap_to_grid = false

    @create_npc_proc = make_block_npc_proc(5)

    @grabbed_entity_id = nil

    @run_start = Time.now.to_f
    @update_count = 0

    @conn = _make_client_connection(hostname, port, self, @player_name, key_size)
    @engine = @conn.engine = ClientEngine.new(self)
    @menu = build_top_menu
    @dialog = PasswordDialog.new(self, @font)
  end

  def _make_client_connection(*args)
    ClientConnection.new(*args)
  end

  def player_id=(id); @player_id = id.to_sym; end

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
      @snap_to_grid ? "Turn snap off" : "Turn snap on"
    end

    Menu.new('Object creation', self, @font,
      MenuItem.new('Object type', self, @font) { object_type_menu },
      MenuItem.new(snap_text, self, @font) do
        @snap_to_grid = !@snap_to_grid
      end,
      MenuItem.new('Save!', self, @font) { @conn.send_save }
    )
  end

  def object_type_menu
    Menu.new('Object type', self, @font, *object_type_submenus)
  end

  def object_type_submenus
    [
      ['Dirt',        make_block_npc_proc( 5) ],
      ['Brick',       make_block_npc_proc(10) ],
      ['Cement',      make_block_npc_proc(15) ],
      ['Steel',       make_block_npc_proc(20) ],
      ['Unlikelium',  make_block_npc_proc(25) ],
      ['Titanium',    make_block_npc_proc( 0) ],
      ['Teleporter',  make_teleporter_npc_proc],
      ['Hole',        make_hole_npc_proc      ],
      ['Base',        make_base_npc_proc      ],
      ['Slime',       make_slime_npc_proc     ],
    ].collect do |type_name, p|
      MenuItem.new(type_name, self, @font) { @create_npc_proc = p }
    end
  end

  def media(filename)
    "#{File.dirname __FILE__}/../../media/#{filename}"
  end

  def space
    @engine.space
  end

  def tick
    @engine.tick
  end

  def player
    return unless space
    warn "GameClient#player(): No such entity #{@player_id}" unless space[@player_id]
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
      warn "@conn.update() averages #{@conn_update_total / @conn_update_count} seconds each" if (@conn_update_count % 60) == 0
    end
    return unless @engine.world_established?

    before_t = Time.now.to_f
    @engine.update
    if @profile
      @engine_update_total += (Time.now.to_f - before_t)
      @engine_update_count += 1
      warn "@engine.update() averages #{@engine_update_total / @engine_update_count} seconds" if (@engine_update_count % 60) == 0
    end

    # Player at the keyboard queues up a command
    # @pressed_buttons is emptied by handle_input
    handle_input if @player_id

    move_grabbed_entity

    warn "Updates per second: #{@update_count / (Time.now.to_f - @run_start)}" if @profile
  end

  def move_grabbed_entity(divide_by = ClientConnection::ACTION_DELAY)
    return unless @grabbed_entity_id
    return unless grabbed = space[@grabbed_entity_id]
    dest_x, dest_y = mouse_entity_location
    vel_x = Entity.constrain_velocity((dest_x - grabbed.x) / divide_by)
    vel_y = Entity.constrain_velocity((dest_y - grabbed.y) / divide_by)
    @conn.send_update_entity(
      :registry_id => grabbed.registry_id,
      :velocity => [vel_x, vel_y],
      :moving => true)
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
        elsif @player_id
          generate_move_from_click
        end
      when Gosu::MsRight then # right-click
        if button_down?(Gosu::KbRightShift) || button_down?(Gosu::KbLeftShift)
          @create_npc_proc.call
        else
          toggle_grab
        end
      when Gosu::KbB then @create_npc_proc.call
      when Gosu::Kb1 then @create_npc_proc = make_block_npc_proc( 5).call
      when Gosu::Kb2 then @create_npc_proc = make_block_npc_proc(10).call
      when Gosu::Kb3 then @create_npc_proc = make_block_npc_proc(15).call
      when Gosu::Kb4 then @create_npc_proc = make_block_npc_proc(20).call
      when Gosu::Kb5 then @create_npc_proc = make_block_npc_proc(25).call
      when Gosu::Kb6 then @create_npc_proc = make_block_npc_proc( 0).call
      when Gosu::Kb7 then @create_npc_proc = make_teleporter_npc_proc.call
      when Gosu::Kb8 then @create_npc_proc = make_hole_npc_proc.call
      when Gosu::Kb9 then @create_npc_proc = make_base_npc_proc.call
      when Gosu::Kb0 then @create_npc_proc = make_slime_npc_proc.call
      when Gosu::KbDelete then send_delete_entity
      when Gosu::KbBracketLeft then rotate_left
      when Gosu::KbBracketRight then rotate_right
      else @pressed_buttons << id unless @dialog
    end
  end

  def generate_move_from_click
    move = player.generate_move_from_click(*mouse_coords)
    @conn.send_move(player_id, *move) if move
  end

  # X/Y position of the mouse (center of the crosshairs), adjusted for camera
  def mouse_coords
    # For some reason, Gosu's mouse_x/mouse_y return Floats, so round it off
    [
      (mouse_x.round + @camera_x) * PIXEL_WIDTH,
      (mouse_y.round + @camera_y) * PIXEL_WIDTH
    ]
  end

  def mouse_entity_location
    x, y = mouse_coords

    if @snap_to_grid
      # When snap is on, we want the upper-left corner of the cell we point at
      return (x / WIDTH) * WIDTH, (y / HEIGHT) * HEIGHT
    else
      # When snap is off, we are pointing at the entity's center, not
      # its upper-left corner
      return x - WIDTH / 2, y - HEIGHT / 2
    end
  end

  def make_block_npc_proc(hp)
    type = hp.zero? ? 'Entity::Titanium' : 'Entity::Block'
    proc { send_create_npc type, :hp => hp }
  end

  def make_teleporter_npc_proc
    proc do
      send_create_npc 'Entity::Teleporter', :on_create => make_destination_npc_proc
    end
  end

  def make_destination_npc_proc
    proc do |teleporter|
      send_create_npc 'Entity::Destination', :owner => teleporter.registry_id,
        :on_create => make_grab_destination_proc
    end
  end

  def make_grab_destination_proc
    proc do |destination|
      grab_specific destination.registry_id
    end
  end

  def make_simple_npc_proc(type); proc { send_create_npc "Entity::#{type}" }; end

  def make_hole_npc_proc; make_simple_npc_proc 'Hole'; end
  def make_base_npc_proc; make_simple_npc_proc 'Base'; end
  def make_slime_npc_proc
    proc do
      send_create_npc 'Entity::Slime', :angle => 270
    end
  end

  def send_create_npc(type, args={})
    @conn.send_create_npc({
      :class => type,
      :position => mouse_entity_location,
      :velocity => [0, 0],
      :angle => 0,
      :moving => true
    }.merge(args))
  end

  def grab_specific(registry_id)
    @grabbed_entity_id = registry_id
  end

  # Actions that modify or delete an existing entity will affect:
  # * The grabbed entity, if there is one, or
  # * The entity under the mouse whose center is closest to the mouse
  def selected_object
    if @grabbed_entity_id
      grabbed = space[@grabbed_entity_id]
      return grabbed if grabbed
    end
    space.near_to(*mouse_coords)
  end

  def toggle_grab
    if @grabbed_entity_id
      @conn.send_snap_to_grid(space[@grabbed_entity_id]) if @snap_to_grid
      return @grabbed_entity_id = nil
    end

    @grabbed_entity_id = space.near_to(*mouse_coords).nullsafe_registry_id
  end

  def adjust_angle(adjustment)
    return unless target = selected_object
    @conn.send_update_entity(
      :registry_id => target.registry_id,
      :angle => target.a + adjustment,
      :moving => true # wake it up
    )
  end

  def rotate_left; adjust_angle(-90); end
  def rotate_right; adjust_angle(+90); end

  def send_delete_entity
    return unless target = selected_object
    @conn.send_delete_entity target
  end

  def shutdown
    @conn.disconnect
    close
  end

  # Dequeue an input event
  def handle_input
    return unless player # can happen when spawning
    return if player.should_fall? || @dialog
    move = move_for_keypress
    @conn.send_move player_id, move # also creates a delta in the engine
  end

  # Check keyboard, mouse, and pressed-button queue
  # Return a motion symbol or nil
  def move_for_keypress
    # Generated once for each keypress
    until @pressed_buttons.empty?
      move = player.move_for_keypress(@pressed_buttons.shift)
      return move if move
    end

    # Continuously-generated when key held down
    player.moves_for_key_held.each do |key, move|
      return move if button_down?(key)
    end

    nil
  end
end
