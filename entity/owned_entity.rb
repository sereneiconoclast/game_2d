class Entity

class OwnedEntity < Entity
  attr_accessor :owner_id

  def owner
    fail "Can't look up owner when not in a space" unless @space
    @space[@owner_id]
  end

  def owner=(new_owner)
    @owner_id = new_owner.nullsafe_registry_id
  end

  def additional_state; { :owner => @owner_id } end
  def update_from_json(json)
    @owner_id = json['owner']

    # Call this now if we're already in the space
    # Otherwise, it'll be called during space << block
    on_added_to_space if @space

    super
  end

  def update_my_owner(new_owner_id)
    @owner_id = new_owner_id
  end

  def on_added_to_space
    update_my_owner(@owner_id)
  end
end

end