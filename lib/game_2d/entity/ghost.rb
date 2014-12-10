require 'game_2d/entity'
require 'game_2d/move/spawn'
require 'game_2d/player'

# A player object that represents the player when between corporeal
# incarnations
#
# Ghost can fly around and look at things, but can't touch or affect
# anything
class Entity

class Ghost < Entity
  include Player
  include Comparable

  MOVES_FOR_KEY_HELD = {
    Gosu::KbLeft  => :left,
    Gosu::KbA     => :left,
    Gosu::KbRight => :right,
    Gosu::KbD     => :right,
    Gosu::KbUp    => :up,
    Gosu::KbW     => :up,
    Gosu::KbDown  => :down,
    Gosu::KbS     => :down,
  }

  def initialize(player_name = "<unknown>")
    super
    initialize_player
    @player_name = player_name
    @score = 0
  end

  def sleep_now?; false; end

  def should_fall?; false; end

  def teleportable?; false; end

  def update
    fail "No space set for #{self}" unless @space

    return if perform_complex_move

    if args = next_move
      case (current_move = args.delete(:move).to_sym)
        when :left, :right, :up, :down
          send current_move
        when :spawn
          spawn args[:x], args[:y]
        else
          puts "Invalid move for #{self}: #{current_move}, #{args.inspect}"
      end
    else
      slow_by 1
    end
    super
  end

  def left; accelerate(-1, 0); end
  def right; accelerate(1, 0); end
  def up; accelerate(0, -1); end
  def down; accelerate(0, 1); end

  def spawn(x, y)
    if base = @space.available_base_near(x, y)
      warn "#{self} spawning at #{base.x}, #{base.y}"
      self.complex_move = Move::Spawn.new
      self.complex_move.target_id = base.registry_id
    end
  end

  # Called by GameWindow
  # Should return a map where the keys are... keys, and the
  # values are the corresponding moves to be sent via
  # ClientConnection
  # This is for non-queued keypresses, i.e. those that happen
  # continuously for as long as held down
  def moves_for_key_held
    MOVES_FOR_KEY_HELD
  end

  # Called by GameWindow
  # Should return the move to be sent via ClientConnection
  # (or nil)
  # This is for queued keypresses, i.e. those that happen
  # on key-down only (just once for a press), not continuously
  # for as long as held down
  def move_for_keypress(keypress); nil; end

  # Called by GameWindow
  # Should return the move to be sent via ClientConnection
  # (or nil)
  def generate_move_from_click(x, y)
    [:spawn, {:x => x, :y => y}]
  end

  def all_state
    # Player name goes first, so we can sort on that
    super.unshift(player_name).push(score, @complex_move)
  end

  def as_json
    super.merge!(
      :player_name => player_name,
      :score => score,
      :complex_move => @complex_move.as_json
    )
  end

  def update_from_json(json)
    @player_name = json[:player_name] if json[:player_name]
    @score = json[:score] if json[:score]
    @complex_move = Serializable.from_json(json[:complex_move]) if json[:complex_move]
    super
  end

  def image_filename; "ghost.png"; end

  def draw_image(anim)
    # Usually frame 0, occasionally frame 1
    anim[((Gosu::milliseconds / 100) % 63) / 62]
  end
end

end
