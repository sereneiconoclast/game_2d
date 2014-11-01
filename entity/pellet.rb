require 'entity/block'
require 'entity/owned_entity'

class Entity

class Pellet < OwnedEntity
  def should_fall?; true end
  def sleep_now?; false end

  # Pellets don't hit the originating player, or other
  # pellets fired by the same player
  def transparent_to_me?(other)
    super ||
    other == self.owner ||
    ((other.is_a?(Pellet) || other.is_a?(Block)) && other.owner == self.owner)
  end

  def i_hit(others)
    puts "#{self}: hit #{others.inspect}.  That's all for me."
    others.each {|other| other.harmed_by(self)}
    @space.doom(self)
  end

  def image_filename; "media/pellet.png" end
end

end
