class Entity

class Block < Entity
  MAX_LEVEL = 5
  HP_PER_LEVEL = 5
  MAX_HP = MAX_LEVEL * HP_PER_LEVEL

  attr_accessor :owner
  attr_reader :hp

  def hp=(p); @hp = [[p, MAX_HP].min, 0].max; end

  def additional_state
    {
      :hp => hp,
      :owner => (owner ? owner.registry_id : nil),
    }
  end

  def update_from_json(json)
    self.hp = json['hp'] if json['hp']
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

  def should_fall?
    return false if owner || !empty_underneath?

    case level
      when 0
        true
      when 1
        empty_on_left? || empty_on_right?
      when 2
        empty_on_left? && empty_on_right?
      when 3
        empty_on_left? && empty_on_right? && empty_above?
      when 4
        false
    end
  end

  def update
    if should_fall?
      accelerate(0, 1)
    else
      self.x_vel = self.y_vel = 0
    end
    move
  end

  def transparent_to_me?(other)
    super ||
    (other == owner) ||
    (other.is_a?(Pellet) && other.owner == self)
  end

  def harmed_by(other)
    puts "#{self}: Ouch!"
    self.hp -= 1
    @space.doom(self) if hp <= 0
  end

  def destroy!
    owner.disown_block if owner
  end

  def level; (hp - 1) / HP_PER_LEVEL; end

  def level_name
    %w(dirt brick cement steel unlikelium)[level]
  end

  def image_filename; "media/#{level_name}.gif"; end
end

end
