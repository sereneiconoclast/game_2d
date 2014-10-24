class Entity

class Pellet < Entity
  attr_accessor :owner

  def additional_state; { :owner => owner.registry_id } end
  def update_from_json(json)
    @owner = @space[json['owner']]
    super
  end

  def should_fall?; true end
  def sleep_now?; false end

  # Pellets don't hit the originating player, or other
  # pellets fired by the same player
  def transparent_to_me?(other)
    super ||
    other == self.owner ||
    (other.is_a?(Pellet) && other.owner == self.owner)
  end

  def i_hit(others)
    puts "#{self}: hit #{others.inspect}.  That's all for me."
    others.each {|other| other.harmed_by(self)}
    @space.doom(self)
  end

  def image_filename; "media/pellet.png" end
end

end
