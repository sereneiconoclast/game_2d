require 'gosu'
require 'game_2d/zorder'

class Message
  def initialize(window, font, lines)
    @window, @font, @lines = window, font, lines

    @fg_color, @bg_color = Gosu::Color::YELLOW, Gosu::Color::BLACK
    @justify = :center
    @drawn = false
    @draw_count = 0
  end

  attr_reader :lines, :draw_count
  attr_accessor :justify

  def lines=(new_lines)
    @lines, @drawn = new_lines, false
  end

  def draw
    @draw_count += 1
    count = @lines.size
    line_height = @font.height
    lines_height = line_height * count
    lines_top = (@window.height - (count * line_height)) / 2
    x_center = @window.width / 2
    max_width = @lines.collect {|line| @font.text_width(line)}.max
    lines_bottom = lines_top + (line_height * count)
    left = x_center - (max_width / 2)
    right = x_center + (max_width / 2)

    @window.draw_box_at(left - 1, lines_top - 1, right + 1, lines_bottom + 1, @fg_color)
    @window.draw_box_at(left, lines_top, right, lines_bottom, @bg_color)

    x_pos, rel_x =
      case @justify
      when :left then [left, 0.0]
      when :right then [right, 1.0]
      when :center then [x_center, 0.5]
      else fail "Unknown justification #{@justify}"
      end
    @lines.each_with_index do |line, n|
      line_top = lines_top + n * line_height
      line_bottom = line_top + line_height - 1
      draw_line line, n, x_pos, rel_x, line_top, line_bottom
    end
    @drawn = true
  end

  def draw_line(line, line_number, x_pos, rel_x,
                line_top, line_bottom)
    @font.draw_rel(line, x_pos, line_top, ZOrder::Text,
        rel_x, 0.0, 1.0, 1.0, @fg_color)
  end

  def drawn?; @drawn; end

  # Called by GameClient, for special keys like Enter that
  # aren't handled by TextInput
  def button_down(id)
  end
end
