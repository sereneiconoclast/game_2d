require 'gosu'
require 'zorder'

class Menu
  def initialize(name, window, font, *choices)
    @name, @window, @font, @choices = name, window, font, choices

    @main_color, @select_color = Gosu::Color::YELLOW, Gosu::Color::CYAN
    @right = window.width - 1
    @choices.each_with_index do |choice, num|
      choice.x = @right
      choice.y = (num + 2) * 20
    end
  end

  def draw
    @font.draw_rel(@name, @window.width - 1, 0, ZOrder::Text, 1.0, 0.0, 1.0, 1.0,
      @main_color)
    x1, x2, y, c = @right - @font.text_width(@name), @right, 20, @main_color
    @window.draw_box_at(x1, y, x2, y+1, @main_color)
    @choices.each(&:draw)
  end

  # Returns a true value if it handled the click
  # May return a Menu or MenuItem to be set as the new menu to display
  # May return simply 'true' if we should redisplay the top-level menu
  def handle_click
    @choices.collect(&:handle_click).compact.first
  end
end

class MenuItem
  attr_accessor :x, :y
  def initialize(name, window, font, &action)
    @name, @window, @font, @action = name, window, font, action
    @main_color, @select_color, @highlight_color =
      Gosu::Color::YELLOW, Gosu::Color::BLACK, Gosu::Color::CYAN

    # Default position: Upper-right corner
    @x, @y = @window.width - 1, 0
  end

  def mouse_over?
    x, y = @window.mouse_x, @window.mouse_y
    (y >= top) && (y < bottom) && (x > left)
  end

  def left; @x - @font.text_width(@name); end
  def right; @x; end
  def top; @y; end
  def bottom; @y + 20; end

  def draw
    selected = mouse_over?
    color = choose_color(selected)
    @font.draw_rel(to_s, @x, @y, ZOrder::Text, 1.0, 0.0, 1.0, 1.0, color)
    if selected
      @window.draw_box_at(left, top, right, bottom, @highlight_color)
    end
  end

  def choose_color(selected)
    selected ? @select_color : @main_color
  end

  # Returns a true value if it handled the click
  # May return a Menu or MenuItem to be set as the new menu to display
  # May return simply 'true' if we should redisplay the top-level menu
  def handle_click
    return unless mouse_over?
    @action.call || true
  end

  def to_s; @name; end
end
