class NilClass
  def as_json; self end
end

module Serializable
  # Flat list of all object state
  # For sorting purposes, most significant goes first
  def all_state
    []
  end

  # Based on all_state
  def <=>(other)
    self.all_state <=> other.all_state
  end
  def ==(other)
    other.class.equal?(self.class) && other.all_state == self.all_state
  end
  def hash; self.class.hash ^ all_state.hash; end
  def eql?(other); self == other; end

  # Returns a hash which becomes the JSON
  def self.as_json(thing)
    { :class => thing.class.to_s }
  end

  # Based on as_json
  def to_json(*args)
    as_json.to_json(*args)
  end

  # Make our state match what's in the hash
  def update_from_json(hash)
  end

  def to_s
    self.class.name
  end

  def self.from_json(json, generate_id=false)
    return nil unless json
    class_name = json[:class]
    binding.pry unless class_name
    raise "Suspicious class name: #{class_name}" unless
      (class_name == 'Player') ||
      (class_name.start_with? 'Entity::') ||
      (class_name.start_with? 'Move::')
    require class_name.pathize
    clazz = constant(class_name)
    it = clazz.new

    # A registry ID must be specified either in the JSON or by the caller, but
    # not both
    if it.is_a? Registerable
      if generate_id
        fail("Entity #{it} (from #{json.inspect}) already has " +
          "ID #{it.registry_id}, cannot generate") if it.registry_id?
        # Leave it nil - it will be populated when added to a space
      else
        it.registry_id = json[:registry_id]
      end
    elsif generate_id
      fail("#{clazz} is not Registerable")
    end

    it.update_from_json(json)
  end

end