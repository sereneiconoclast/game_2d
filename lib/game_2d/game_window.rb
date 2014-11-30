## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'facets/kernel/try'
require 'gosu'

require 'game_2d/game_client'

# The Gosu::Window is always the "environment" of our game
# It also provides the pulse of our game
class GameWindow < Gosu::Window
  include GameClient

  def initialize(opts = {})
    super(SCREEN_WIDTH, SCREEN_HEIGHT, false, 16)

    @background_image = Gosu::Image.new(self, media("Space.png"), true)
    @animation = Hash.new do |h, k|
      h[k] = Gosu::Image::load_tiles(
        self, k, CELL_WIDTH_IN_PIXELS, CELL_WIDTH_IN_PIXELS, false)
    end

    @cursor_anim = @animation[media("crosshair.gif")]

    @beep = Gosu::Sample.new(self, media("Beep.wav")) # not used yet

    @font = Gosu::Font.new(self, Gosu::default_font_name, 20)

    initialize_from_hash(opts)
  end

  def draw
    @background_image.draw(0, 0, ZOrder::Background)
    @dialog.draw if @dialog
    @message.draw if @message
    @menu.draw if @menu

    cursor_img = @cursor_anim[Gosu::milliseconds / 50 % @cursor_anim.size]
    cursor_img.draw(
      mouse_x - cursor_img.width / 2.0,
      mouse_y - cursor_img.height / 2.0,
      ZOrder::Cursor,
      1, 1, Gosu::Color::WHITE, :add)

    return unless @player_id

    @camera_x, @camera_y = space.good_camera_position_for(player, SCREEN_WIDTH, SCREEN_HEIGHT)
    translate(-@camera_x, -@camera_y) do
      (space.players + space.npcs).each {|entity| entity.draw(self) }
    end

    space.players.sort.each_with_index do |player, num|
      @font.draw("#{player.player_name}: #{player.score}", 10, 10 * (num * 2 + 1), ZOrder::Text, 1.0, 1.0, Gosu::Color::YELLOW)
    end
  end

  def draw_box_at(x1, y1, x2, y2, c)
    draw_quad(x1, y1, c, x2, y1, c, x2, y2, c, x1, y2, c, ZOrder::Highlight)
  end
end
