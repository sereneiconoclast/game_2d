require 'game_2d/entity'

class Entity

class Base < Entity
  def should_fall?; underfoot.empty?; end

  def update
    if should_fall?
      self.a = (direction || 180) + 180
    else
      slow_by 1
    end
    super
  end

  def image_filename; "base.png"; end
end

end
