require 'gosu'
require 'game_2d/message'
require 'game_2d/encryption'

class PasswordDialog < Message
  include Encryption

  PROMPT = 'Enter password:'
  PRINTABLE_ASCII = (32..126).to_a.pack 'C*'

  def initialize(window, font, on_enter)
    super(window, font, [PROMPT, '_'])
    @on_enter = on_enter # proc that accepts a password_hash arg
    @text = @window.text_input = Gosu::TextInput.new
  end

  def display_text
    size = password.size
    return '_' if size.zero?
    rand_char = PRINTABLE_ASCII[
      (draw_count / 10) * 53 % PRINTABLE_ASCII.size
    ]
    rand_char * size
  end

  def draw
    self.lines = [PROMPT, display_text]
    super
  end

  def button_down(id)
    case id
      when Gosu::KbEnter, Gosu::KbReturn then
        @window.text_input = nil
        @on_enter.call password_hash
    end
  end

  def password
    @text.text
  end
  private :password

  def password_hash
    make_password_hash password
  end
end
