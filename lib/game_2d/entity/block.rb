require 'game_2d/entity/owned_entity'

class Entity

class Block < OwnedEntity
  MAX_LEVEL = 5
  HP_PER_LEVEL = 5
  MAX_HP = MAX_LEVEL * HP_PER_LEVEL

  attr_reader :hp

  def hp=(p); @hp = [[p, MAX_HP].min, 0].max; end

  def all_state; super.push(hp); end
  def as_json; super.merge!(:hp => hp); end

  def update_from_json(json)
    self.hp = json[:hp] if json[:hp]
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
    (other.registry_id == owner_id) ||
    (other.is_a?(Pellet) && other.owner_id == owner_id)
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

  def image_filename; "#{level_name}.gif"; end
end

end
