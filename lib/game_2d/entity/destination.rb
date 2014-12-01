require 'game_2d/entity'

class Entity

class Destination < OwnedEntity

  def should_fall?; false; end

  def update; end

  def image_filename; "destination.png"; end

  def draw_zorder; ZOrder::Destination end
end

end
