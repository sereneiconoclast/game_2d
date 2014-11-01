require 'securerandom'

class Object
  def nullsafe_registry_id; nil; end
end

module Registerable
  def registry_id
    @registry_id or raise("No ID set for #{self}")
  end
  def nullsafe_registry_id; registry_id; end

  # For use in to_s
  def registry_id_safe
    @registry_id || '[NO ID]'
  end

  def generate_id
    raise "#{self}: Already have ID #{@registry_id}, cannot set to #{id}" if @registry_id
    @registry_id = SecureRandom.uuid
  end

  def registry_id=(id)
    raise "#{self}: Already have ID #{@registry_id}, cannot set to #{id}" if @registry_id
    raise "#{self}: Invalid ID #{id}" unless id
    @registry_id = id
  end
end
