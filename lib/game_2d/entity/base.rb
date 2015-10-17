require 'game_2d/entity'
require 'game_2d/player'
require 'game_2d/entity/ghost'

class Entity

# Not to be confused with a "base class".  This is a player base,
# a spawn point.
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

  def available?
    return false unless space

    # Can't use entity.entities_obstructing() here, as that only
    # returns objects opaque to the receiver (the base).  Players
    # aren't opaque to bases.  We need to ensure there are no
    # solid (non-ghost) players occupying the space.
    #
    # This logic depends on the fact that anything transparent
    # to a base is also transparent to a player.  If we ever allow
    # a base to go somewhere a player can't be, that's a problem.
    space.entities_overlapping(x, y).find_all do |e|
      e.is_a?(Player) && !e.is_a?(Entity::Ghost)
    end.empty?
  end

  def image_filename; "base.png"; end
end

end
