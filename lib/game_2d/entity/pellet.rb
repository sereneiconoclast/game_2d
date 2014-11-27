require 'game_2d/entity/block'
require 'game_2d/entity/owned_entity'

class Entity

class Pellet < OwnedEntity
  def should_fall?; true end
  def sleep_now?; false end

  def i_hit(others)
    puts "#{self}: hit #{others.inspect}.  That's all for me."
    others.each {|other| other.harmed_by(self)}
    @space.doom(self)
  end

  def image_filename; "pellet.png" end
end

end
