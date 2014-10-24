class Entity

class Block < Entity
  attr_accessor :owner

  def additional_state; owner ? { :owner => owner.registry_id } : {} end
  def update_from_json(json)
    new_owner = @space[json['owner']]

    # This is telling me I need a better solution for keeping
    # the client in sync with the server.  This logic is too
    # complicated and specific.
    if new_owner
      new_owner.build_block = self
    elsif self.owner
      self.owner.build_block = nil
    end

    self.owner = new_owner
    super
  end

  def should_fall?; !owner && empty_underneath?; end

  def transparent_to_me?(other)
    super ||
    (other == owner) ||
    (other.is_a?(Pellet) && other.owner == self)
  end

  def harmed_by(other)
    puts "#{self}: Ouch!"
    @space.doom(self)
  end

  def destroy!
    owner.disown_block if owner
  end

  def image_filename; "media/dirt.gif"; end
end

end
