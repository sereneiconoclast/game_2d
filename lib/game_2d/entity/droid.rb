require 'game_2d/entity'
require 'game_2d/entity/owned_entity'
require 'game_2d/gibber/gibber'

# A player-owned object that can be programmed
class Entity

class Droid < OwnedEntity

  attr_accessor :program
  attr_reader :context

  def initialize(x=0, y=0)
    super(x, y)
    @program = '0'
    @context = nil
    @old_program = nil
    @parser = nil
    @parsed = nil
    @alert = nil
  end

  def sleep_now?; false; end

  def update
    fail "No space set for #{self}" unless @space

    if @program != @old_program
      @old_program = @program
      @context = {}
      @parser = Game2D::GibberParser.new
      unless @parsed = @parser.parse(@program)
        puts "Parsing error at (#{@parser.failure_line}, #{@parser.failure_column})"
        puts @parser.failure_reason
      end
    end

    if @parsed
      begin
        result = @parsed.value(@context)
        @alert = result ? result.to_s : nil
      rescue => e
        @alert = e.to_s
      end
    end
  end

  def all_state; super.push(program, context); end
  def as_json; super.merge!(:program => program, :context => context); end

  def update_from_json(json)
    @program = json[:program] if json[:program]
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
