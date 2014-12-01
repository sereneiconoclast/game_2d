require 'game_2d/entity'

class Entity

class Destination < OwnedEntity

  def should_fall?; false; end

  def update; end

  def image_filename; "destination.png"; end

  def draw_zorder; ZOrder::Destination; end
  def draw_angle; space.game.tick % 360; end
end

end
