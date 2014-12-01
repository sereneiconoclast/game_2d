require 'facets/kernel/try'

class Entity

class OwnedEntity < Entity
  attr_reader :owner_id

  def owner_id=(id)
    old_owner_id, @owner_id = @owner_id, id.try(:to_sym)
    space.owner_change(registry_id, old_owner_id, @owner_id) if space && registry_id?
  end

  def owner
    fail "Can't look up owner when not in a space" unless @space
    @space[@owner_id]
  end

  def owner=(new_owner)
    self.owner_id = new_owner.nullsafe_registry_id
  end

  def all_state; super.push(owner_id); end
  def as_json; super.merge! :owner => owner_id; end
  def update_from_json(json)
    self.owner_id = json[:owner] if json[:owner]
    super
  end
end

end