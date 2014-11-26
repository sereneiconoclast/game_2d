require 'gosu'
require 'game_2d/message'

class PasswordDialog < Message
  PROMPT = 'Enter password:'
  PRINTABLE_ASCII = (32..126).to_a.pack 'C*'

  def initialize(window, font)
    super(window, font, [PROMPT, '_'])
    @text = @window.text_input = Gosu::TextInput.new
    @draw_count = 0
  end

  def display_text
    size = password.size
    return '_' if size.zero?
    rand_char = PRINTABLE_ASCII[
      (@draw_count / 10) * 53 % PRINTABLE_ASCII.size
    ]
    rand_char * size
  end

  def draw
    @draw_count += 1
    self.lines = [PROMPT, display_text]
    super
  end

  def enter
    @window.text_input = nil
  end

  def password
    @text.text
  end
end