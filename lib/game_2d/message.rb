require 'gosu'
require 'game_2d/zorder'

class Message
  def initialize(window, font, lines)
    @window, @font, @lines = window, font, lines

    @fg_color, @bg_color = Gosu::Color::YELLOW, Gosu::Color::BLACK
    @drawn = false
  end

  attr_reader :lines
  def lines=(new_lines)
    @lines, @drawn = new_lines, false
  end

  def draw
    count = @lines.size
    line_height = @font.height
    lines_height = line_height * count
    lines_top = (@window.height - (count * line_height)) / 2
    x_center = @window.width / 2
    @lines.each_with_index do |line, n|
      @font.draw_rel(line, x_center, lines_top + (line_height * n), ZOrder::Text,
        0.5, 0.0, 1.0, 1.0, @fg_color)
    end
    max_width = @lines.collect {|line| @font.text_width(line)}.max
    lines_bottom = lines_top + (line_height * count)
    left = x_center - (max_width / 2)
    right = x_center + (max_width / 2)
    @window.draw_box_at(left - 1, lines_top - 1, right + 1, lines_bottom + 1, @fg_color)
    @window.draw_box_at(left, lines_top, right, lines_bottom, @bg_color)
    @drawn = true
  end

  def drawn?; @drawn; end
end
