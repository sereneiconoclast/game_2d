require 'gosu'
require 'game_2d/entity_constants'
require 'game_2d/zorder'

# The base module representing what all Players have in common
# Moves can be enqueued by calling add_move
# The server instantiates classes that mix in this module, to
# represent each connected player
module Player
  include EntityConstants

  attr_accessor :player_name, :score

  def initialize_player
    @moves = []
  end

  # Accepts a hash, with a key :move => move_type
  def add_move(new_move)
    return unless new_move
    @moves << new_move
  end

  def next_move; @moves.shift; end

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