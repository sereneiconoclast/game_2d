require 'game_2d/entity'
require 'game_2d/entity/block'
require 'game_2d/entity/titanium'
require 'game_2d/entity/owned_entity'
require 'game_2d/entity/teleporter'
require 'game_2d/entity/destination'
require 'game_2d/entity/hole'
require 'game_2d/wall'

module Transparency
  def transparent?(one, two)
    # Walls and titanium: transparent to absolutely nothing
    return false if wall?(one) || wall?(two)

    # Holes and teleporter destinations: transparent to everything
    return true if transparent_to_all?(one) || transparent_to_all?(two)

    # Teleporters: transparent to everything except other
    # teleporters, and destinations
    return teleporter_ok?(one, two) if teleporter?(one)
    return teleporter_ok?(two, one) if teleporter?(two)

    # Owned entities are transparent to the owner, and other
    # objects with the same owner
    return related_by_owner?(one, two) if owned?(one)
    return related_by_owner?(two, one) if owned?(two)

    # Should only get here if both objects are players
    fail("Huh?  one=#{one}, two=#{two}") unless
      one.is_a?(Player) && two.is_a?(Player)
    false
  end

  private
  def wall?(entity)
    entity.is_a?(Wall) || entity.is_a?(Entity::Titanium)
  end

  def teleporter_ok?(tp, other)
    !teleporter?(other)
  end

  def teleporter?(entity)
    entity.is_a?(Entity::Teleporter)
  end

  def transparent_to_all?(entity)
    entity.is_a?(Entity::Destination) || entity.is_a?(Entity::Hole)
  end

  def related_by_owner?(o, other)
    return false unless o.owner
    other.registry_id == o.owner_id ||
      (other.is_a?(Entity::OwnedEntity) && other.owner_id == o.owner_id)
  end

  def owned?(entity)
    entity.is_a? Entity::OwnedEntity
  end
end
