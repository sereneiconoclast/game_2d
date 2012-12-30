require 'entity'
require 'gosu'
require 'zorder'

# The base Player class representing what all Players have in common
# Moves can be enqueued by calling add_move
# Calling update() causes a move to be dequeued and executed, applying forces
# to the game object
#
# The server instantiates this class to represent each connected player
# The connection (conn) is the received one for that player
class Player < Entity
  include Comparable
  attr_reader :conn, :player_name
  attr_accessor :score

  def initialize(space, conn, player_name)
    super(space, 0, 0)
    @conn = conn
    @player_name = player_name
    @score = 0
    @moves = []
    @current_move = nil
  end

  def sleep_now?; false; end

  # Primitive gravity: Accelerate downward if there are no entities underneath
  def update
    if empty_underneath?
      accelerate(0, 1)
    else
      current_move = @moves.shift
      if current_move
        if current_move.is_a? Hash # Currently for 'ping' only
          @conn.send_record :pong => current_move
        elsif [:slide_left, :slide_right, :flip].include? current_move
          send current_move
        else
          puts "Invalid move for #{self}: #{current_move}"
        end
      end
    end

    super
  end

  def slide_left
    accelerate(*angle_to_vector(self.a - 90))
  end

  def slide_right
    accelerate(*angle_to_vector(self.a + 90))
  end

  def flip
  end

  def add_move(new_move)
    @moves << new_move if new_move
  end

  def <=>(other)
    self.player_name <=> other.player_name
  end

  def to_s
    "#{player_name} (#{registry_id}) at #{x}x#{y}"
  end

  def as_json
    super().merge(
      :class => 'Player',
      :player_name => player_name,
      :score => score
    )
  end

  def update_from_json(json)
    @player_name = json['player_name']
    @score = json['score']
    super
  end

  def image_filename; "media/gize0-up.gif"; end

  def draw(window)
    super
    window.font.draw_rel(player_name,
      pixel_x + CELL_WIDTH_IN_PIXELS / 2, pixel_y, ZOrder::Text,
      0.5, 1.0, # Centered X; above Y
      1.0, 1.0, Gosu::Color::YELLOW)
  end

  def handle_input(window)
    move = move_for_keypress(window)
    @conn.send_move move
    add_move move
  end

  # Check keyboard, return a motion symbol or nil
  def move_for_keypress(window)
    case
    when window.button_down?(Gosu::KbLeft) then :slide_left
    when window.button_down?(Gosu::KbRight) then :slide_right
    when window.button_down?(Gosu::KbUp) then :flip
    when window.button_down?(Gosu::KbP) then @conn.send_ping
    end
  end
end
