require 'game_2d/entity'
require 'game_2d/entity/owned_entity'
require 'game_2d/gibber/gibber'

# A player-owned object that can be programmed
class Entity

class Droid < OwnedEntity

  attr_reader :program, :heap

  def initialize(x=0, y=0)
    super(x, y)
    @program = '0'
    @compiled_program = nil
    @vm = nil
    @alert = nil
    @falling = nil
  end

  def program!(new_program)
    return if @compiled_program == new_program && @parsed

    @program = new_program
    parser = Game2D::GibberParser.new
    unless parsed = parser.parse(@program)
      @alert = "Parsing error at (#{parser.failure_line}, #{parser.failure_column})"
      warn parser.failure_reason
      @vm = nil
      return
    end
    @vm = parsed.compile
    @vm.owner = self
    @vm.reset!
    @compiled_program = @program
  end

  def sleep_now?; false; end

  def should_fall?; empty_underneath?; end
  def falling?; @falling; end

  def update
    fail "No space set for #{self}" unless @space

    if @falling = should_fall?
      space.fall(self)
    end

    if @vm
      @vm.reset! if @vm.done?
      begin
        @vm.execute(10)
        result = @vm.last
        @alert = result ? result.to_s : nil
      rescue => e
        @alert = e.to_s
        @vm.reset!
      end
    end

    move
  end

  def all_state; super.push(@program, @vm); end
  def as_json
    super.merge!(
      :program => @program,
      :vm => (@vm ? @vm.as_json : nil)
    )
  end

  def update_from_json(json)
    @program = json[:program] if json[:program]

    if json[:vm]
      @vm = Game2D::Gibber::VM.new
      @vm.update_from_json(json[:vm])
      @vm.owner = self
      @compiled_program = @program
    else
      @vm = @compiled_program = nil
    end
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
