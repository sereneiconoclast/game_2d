require 'game_2d/entity'
require 'game_2d/entity/owned_entity'
require 'game_2d/gibber/gibber'

# A player-owned object that can be programmed
class Entity

class Droid < OwnedEntity

  attr_reader :program, :context

  def initialize(x=0, y=0)
    super(x, y)
    @program = '0'
    @context = nil
    @compiled_program = nil
    @parsed = nil
    @alert = nil
    @falling = nil
  end

  def program=(new_program)
    return if @compiled_program == new_program && @parsed

    @program = new_program
    parser = Game2D::GibberParser.new
    unless @parsed = parser.parse(@program)
      @alert = "Parsing error at (#{parser.failure_line}, #{parser.failure_column})"
      warn parser.failure_reason
      return
    end
    @compiled_program = @program
    @context = {}
  end

  def sleep_now?; false; end

  def should_fall?; empty_underneath?; end
  def falling?; @falling; end

  def update
    fail "No space set for #{self}" unless @space

    if @falling = should_fall?
      space.fall(self)
    end

    if @parsed
      begin
        result = @parsed.value(self, @context)
        @alert = result ? result.to_s : nil
      rescue => e
        @alert = e.to_s
      end
    end

    move
  end

  def all_state; super.push(program, context); end
  def as_json; super.merge!(:program => program, :context => context); end

  def update_from_json(json)
    # Storing a new program will clear the context
    # So we do that first
    self.program = json[:program] if json[:program]

    @context = json[:context] if json[:context]
    super
  end

  def image_filename; "droid.png"; end

  FRAMES = [0, 1, 2, 3, 2, 1]
  def draw_image(anim)
    frame = Gosu::milliseconds / 100 % 6
    anim[FRAMES[frame]]
  end

  def draw(window)
    super
    return unless @alert
    window.font.draw_rel(@alert,
      pixel_x + CELL_WIDTH_IN_PIXELS / 2, pixel_y, ZOrder::Text,
      0.5, 1.0, # Centered X; above Y
      1.0, 1.0, Gosu::Color::YELLOW)
  end
end

end
