require 'entity'
require 'gosu'
require 'zorder'

# The base Player class representing what all Players have in common
# Moves can be enqueued by calling add_move
# Calling dequeue_move causes a move to be executed, applying forces
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

  # TODO...
  def turn_left
  end

  def turn_right
  end

  def accelerate
  end

  def boost
  end

  def reverse
  end

  def add_move(new_move)
    @moves << new_move if new_move
  end

  def dequeue_move
    @current_move = @moves.shift
  end

  def execute_move
    return unless @current_move

    if @current_move.is_a? Hash # Currently for 'ping' only
      @conn.send_record :pong => @current_move
      return nil
    elsif [:turn_left, :turn_right, :accelerate, :boost, :reverse].include? @current_move
      send @current_move
      return @current_move
    else
      puts "Invalid move for #{self}: #{@current_move}"
      return nil
    end
  end

  def <=>(other)
    self.player_name <=> other.player_name
  end

  def to_s
    "#{player_name} (#{registry_id})"
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
    self.x, self.y = json['position']
    self.x_vel, self.y_vel = json['velocity']
    self.moving = json['moving']
    self.a = json['angle']
    # TODO @body.w = json['angular_vel'] # radians/second
  end
end

# Subclass representing a player client-side
# Adds drawing capability
# We instantiate this class directly to represent remote players (not the one
# at the keyboard)
# Instances of this class will not have a connection (conn) because players
# aren't directly connected to each other
class ClientPlayer < Player
  def initialize(space, conn, player_name, window)
    super(space, conn, player_name)
    @window = window
    @image = Gosu::Image.new(window, "media/Starfighter.bmp", false)
  end

  def draw
    @image.draw_rot(self.pixel_x, self.pixel_y, ZOrder::Objects, self.a)
  end
end

# Subclass representing the player at the controls of this client
# This is different in that we check the keyboard, and send moves
# to the server in addition to dequeueing them
class LocalPlayer < ClientPlayer
  def initialize(space, conn, player_name, window)
    super
  end

  def handle_input
    move = move_for_keypress
    @conn.send_move move
    add_move move
  end

  # Check keyboard, return a motion symbol or nil
  def move_for_keypress
    case
    when @window.button_down?(Gosu::KbLeft) then :turn_left
    when @window.button_down?(Gosu::KbRight) then :turn_right
    when @window.button_down?(Gosu::KbUp) then
      if @window.button_down?(Gosu::KbRightShift) || @window.button_down?(Gosu::KbLeftShift)
        :boost
      else
        :accelerate
      end
    when @window.button_down?(Gosu::KbDown) then :reverse
    when @window.button_down?(Gosu::KbP) then @conn.send_ping
    end
  end
end
