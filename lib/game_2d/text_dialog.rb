require 'gosu'
require 'game_2d/message'

class TextDialog < Message
  BLINK_RATE = 16

  def initialize(window, font = nil, initial_lines = nil)
    font ||= Gosu::Font.new(window, "Courier", 16)
    initial_lines ||= ['']
    super(window, font, initial_lines)
    @select_color = Gosu::Color::CYAN
    @justify = :left
    @line_number = 0
    @cursor_pos = 0
    @select_line = 0
    @select_pos = 0
  end

  def draw_line(line, line_number, x_pos, rel_x, x_min, x_max,
                line_top, line_bottom)
    super
    this_line = @lines[line_number]

    sel_begin, sel_end = selected_part_of_line(line_number)
    if sel_begin
      t_before, t_after =
        this_line[0...sel_begin], this_line[sel_end..-1]
      x_sel_begin = x_min + @font.text_width(t_before)
      x_sel_end = x_max - @font.text_width(t_after)
      @window.draw_box_at(x_sel_begin, line_top,
                          x_sel_end, line_bottom,
                          @select_color)
    end

    return unless draw_count % BLINK_RATE > (BLINK_RATE / 2)
    if line_number == @line_number
      substr = this_line[0...@cursor_pos]
      cursor_x = x_pos + @font.text_width(substr)

      @window.draw_box_at(cursor_x - 1, line_top,
                          cursor_x + 1, line_bottom,
                          @fg_color)
    end
  end

  # If the selection intersects this line, returns an array
  # indicating which characters of the line are selected
  # Otherwise, returns nil
  def selected_part_of_line(line_number)
    start_line, start_pos, end_line, end_pos = sort_locations

    # No selection
    if start_line == end_line && start_pos == end_pos
      return nil

    # This line is entirely outside selection
    elsif start_line > line_number || end_line < line_number
      return nil
    end

    sel_begin = start_line < line_number ? 0 : start_pos
    sel_end = end_line > line_number ? @lines[line_number].size : end_pos
    return nil if sel_begin == sel_end
    return [sel_begin, sel_end]
  end

  def sort_locations(
    line1=@line_number, pos1=@cursor_pos,
    line2=@select_line, pos2=@select_pos
  )
    if line1 < line2
      [line1, pos1, line2, pos2]
    elsif line1 > line2
      [line2, pos2, line1, pos1]
    elsif pos1 <= pos2
      [line1, pos1, line2, pos2]
    else
      [line2, pos2, line1, pos1]
    end
  end

  def button_down(id)
    ctrl = @window.button_down?(Gosu::KbLeftControl) ||
           @window.button_down?(Gosu::KbRightControl)
    shift = @window.button_down?(Gosu::KbLeftShift) ||
            @window.button_down?(Gosu::KbRightShift)

    should_void_selection = case id
    when Gosu::KbHome
      if ctrl then start_of_buffer else start_of_line end
    when Gosu::KbEnd
      if ctrl then end_of_buffer else end_of_line end
    when Gosu::KbLeft
      if ctrl then prev_word else prev_char end
    when Gosu::KbRight
      if ctrl then next_word else next_char end
    when Gosu::KbUp then prev_line
    when Gosu::KbDown then next_line
    when Gosu::KbBackspace then backspace
    when Gosu::KbDelete then delete
    when Gosu::KbReturn, Gosu::KbEnter then enter
    else insert_char(id, shift)
    end

    void_selection if should_void_selection || !shift
  end

  def void_selection
    @select_line, @select_pos = @line_number, @cursor_pos
  end

  def start_of_line
    @cursor_pos = 0
    false
  end

  def start_of_buffer
    @line_number = 0
    start_of_line
  end

  def end_of_line
    @cursor_pos = this_line.size
    false
  end

  def end_of_buffer
    @line_number = @lines.size - 1
    end_of_line
  end

  def next_line
    if @line_number < @lines.size - 1
      @line_number += 1
      @cursor_pos = [this_line.size, @cursor_pos].min
    end
    false
  end

  def prev_line
    if @line_number > 0
      @line_number -= 1
      @cursor_pos = [this_line.size, @cursor_pos].min
    end
    false
  end

  def next_char
    if @cursor_pos < this_line.size
      @cursor_pos += 1
    elsif @line_number < @lines.size - 1
      @line_number += 1
      @cursor_pos = 0
    end
    false
  end

  def prev_char
    if @cursor_pos > 0
      @cursor_pos -= 1
    elsif @line_number > 0
      @line_number -= 1
      @cursor_pos = this_line.size
    end
    false
  end

  def next_word
    if @cursor_pos < this_line.size &&
    find_next = this_line.index(/\b\w/, @cursor_pos + 1)
      @cursor_pos = find_next
    elsif @line_number < @lines.size - 1
      @line_number += 1
      find_next = this_line.index /\b\w/
      @cursor_pos = find_next || this_line.size
    else
      @cursor_pos = this_line.size
    end
    false
  end

  def prev_word
    if @cursor_pos > 0 &&
    find_next = this_line.rindex(/\b\w/, @cursor_pos - 1)
      @cursor_pos = find_next
    elsif @line_number > 0
      @line_number -= 1
      find_next = this_line.rindex /\b\w/
      @cursor_pos = find_next || 0
    else
      @cursor_pos = 0
    end
    false
  end

  def backspace
    if @cursor_pos > 0
      @lines[@line_number] =
        this_line[0...@cursor_pos - 1] +
        this_line[@cursor_pos..-1]
      @cursor_pos -= 1
      true
    elsif @line_number > 0
      prev_char
      @lines[@line_number] += @lines.delete_at(@line_number + 1)
      true
    end
  end

  def delete
    if @cursor_pos < this_line.size
      @lines[@line_number] =
        this_line[0...@cursor_pos] +
        this_line[(@cursor_pos+1)..-1]
      true
    elsif @line_number < @lines.size - 1
      @lines[@line_number] += @lines.delete_at(@line_number + 1)
      true
    end
  end

  def enter
    after = this_line[@cursor_pos..-1]
    @lines[@line_number] = this_line[0...@cursor_pos]
    @line_number += 1
    @lines.insert @line_number, after
    @cursor_pos = 0
    true
  end

  def insert_char(id, shift)
    if ch = CHAR_TABLE[id]
      ch = ch[shift ? -1 : 0]
      @lines[@line_number] =
        this_line[0...@cursor_pos] + ch +
        this_line[@cursor_pos..-1]
      @cursor_pos += 1
      true
    end
  end

  def this_line
    @lines[@line_number]
  end

  CHAR_TABLE = {
    Gosu::KbA => ['a', 'A'],
    Gosu::KbB => ['b', 'B'],
    Gosu::KbC => ['c', 'C'],
    Gosu::KbD => ['d', 'D'],
    Gosu::KbE => ['e', 'E'],
    Gosu::KbF => ['f', 'F'],
    Gosu::KbG => ['g', 'G'],
    Gosu::KbH => ['h', 'H'],
    Gosu::KbI => ['i', 'I'],
    Gosu::KbJ => ['j', 'J'],
    Gosu::KbK => ['k', 'K'],
    Gosu::KbL => ['l', 'L'],
    Gosu::KbM => ['m', 'M'],
    Gosu::KbN => ['n', 'N'],
    Gosu::KbO => ['o', 'O'],
    Gosu::KbP => ['p', 'P'],
    Gosu::KbQ => ['q', 'Q'],
    Gosu::KbR => ['r', 'R'],
    Gosu::KbS => ['s', 'S'],
    Gosu::KbT => ['t', 'T'],
    Gosu::KbU => ['u', 'U'],
    Gosu::KbV => ['v', 'V'],
    Gosu::KbW => ['w', 'W'],
    Gosu::KbX => ['x', 'X'],
    Gosu::KbY => ['y', 'Y'],
    Gosu::KbZ => ['z', 'Z'],
    Gosu::KbBacktick => ['`', '~'],
    Gosu::Kb1 => ['1', '!'],
    Gosu::Kb2 => ['2', '@'],
    Gosu::Kb3 => ['3', '#'],
    Gosu::Kb4 => ['4', '$'],
    Gosu::Kb5 => ['5', '%'],
    Gosu::Kb6 => ['6', '^'],
    Gosu::Kb7 => ['7', '&'],
    Gosu::Kb8 => ['8', '*'],
    Gosu::Kb9 => ['9', '('],
    Gosu::Kb0 => ['0', ')'],
    Gosu::KbMinus => ['-', '_'],
    Gosu::KbEqual => ['=', '+'],
    Gosu::KbBracketLeft => ['[', '{'],
    Gosu::KbBracketRight => [']', '}'],
    Gosu::KbSemicolon => [';', ':'],
    Gosu::KbApostrophe => ["'", '"'],
    Gosu::KbComma => [',', '<'],
    Gosu::KbPeriod => ['.', '>'],
    Gosu::KbSpace => [' '],
    Gosu::KbBackslash => ['\\', '|'],
    # For some reason Gosu thinks my backslash key is my
    # slash key. KbSlash == KbBackslash
    56 => ['/', '?']
  }
end
