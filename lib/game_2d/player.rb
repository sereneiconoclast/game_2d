require 'gosu'
require 'game_2d/entity_constants'
require 'game_2d/zorder'

# The base module representing what all Players have in common
# Moves can be enqueued by calling add_move
# The server instantiates classes that mix in this module, to
# represent each connected player
module Player
  include EntityConstants

  attr_accessor :player_name, :score, :complex_move

  def initialize_player
    @moves = []
    @complex_move = nil
  end

  # Returns true if a complex move is in process, and took
  # some action
  # Returns nil if the complex move completed, or there isn't one
  def perform_complex_move
    return unless @complex_move

    # returns true if more work to do
    return true if @complex_move.update(self)

    @complex_move.on_completion(self)
    @complex_move = nil
  end

  # Accepts a hash, with a key :move => move_type
  def add_move(new_move)
    return unless new_move
    @moves << new_move
  end

  def next_move; @moves.shift; end

  def replace_player_entity(new_entity)
    if (game = space.game).is_a? GameClient
      game.player_id = new_entity.registry_id if game.player_id == registry_id
    else
      game.replace_player_entity(player_name, new_entity.registry_id)
    end
    space.doom(self)
  end

  def die
    ghost = Entity::Ghost.new(player_name)
    ghost.x, ghost.y, ghost.a, ghost.x_vel, ghost.y_vel, ghost.score =
      x, y, 0, x_vel, y_vel, score
    return unless space << ghost # coast to coast

    replace_player_entity ghost
  end

  def draw_zorder; ZOrder::Player end

  def draw(window)
    super
    window.font.draw_rel(player_name,
      pixel_x + CELL_WIDTH_IN_PIXELS / 2, pixel_y, ZOrder::Text,
      0.5, 1.0, # Centered X; above Y
      1.0, 1.0, Gosu::Color::YELLOW)
  end

  def to_s
    "#{player_name} (#{self.class.name} #{registry_id_safe}) at #{x}x#{y}"
  end
end