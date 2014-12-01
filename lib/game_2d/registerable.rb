class NilClass
  def nullsafe_registry_id; self; end
end

module Registerable
  def registry_id?
    @registry_id
  end

  def registry_id
    @registry_id or raise("No ID set for #{self}")
  end
  def nullsafe_registry_id; registry_id; end

  # For use in to_s
  def registry_id_safe
    @registry_id || :NO_ID
  end

  def registry_id=(id)
    raise "#{self}: Already have ID #{@registry_id}, cannot set to #{id}" if @registry_id
    raise "#{self}: Nil ID" unless id
    @registry_id = id.to_sym
  end
end
