class Entity

class OwnedEntity < Entity
  attr_accessor :owner_id
  attr_reader :owner

  def owner=(new_owner)
    @owner = new_owner
    @owner_id = new_owner.nullsafe_registry_id
  end

  def additional_state; { :owner => owner.nullsafe_registry_id } end
  def update_from_json(json)
    @owner_id = json['owner']

    # Call this now if we're already in the space
    # Otherwise, it'll be called during space << block
    on_added_to_space if @space

    super
  end

  # This is telling me I need a better solution for keeping
  # the client in sync with the server.  This logic is too
  # complicated and specific.
  def update_my_owner(new_owner)
    return if new_owner == self.owner

    new_owner.build_block = self if new_owner
    self.owner.build_block = nil if self.owner

    self.owner = new_owner
  end

  def on_added_to_space
    update_my_owner(@space[@owner_id])
  end
end

end