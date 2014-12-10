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
        !(supported_on_left && supported_on_right)
      when 2
        !(supported_on_left || supported_on_right)
      when 3
        empty_on_left? && empty_on_right? && empty_above?
      when 4
        false
    end
  end

  def supported_on_left
    opaque(space.entities_exactly_at_point(x - WIDTH, y)).any?
  end

  def supported_on_right
    right_support = opaque(space.entities_exactly_at_point(x + WIDTH, y)).any?
  end

  def update
    if should_fall?
      # applies acceleration, but that's all
      space.fall(self)
    else
      self.x_vel = self.y_vel = 0
    end
    # Reduce velocity if necessary, to exactly line up with
    # an upcoming source of support (so we don't move past it)
    if x_vel == 0 && y_vel != 0
      case level
        when 1
          new_y = look_ahead_for_support_both_sides
          self.y_vel = new_y - y if new_y
        when 2
          new_y = look_ahead_for_support_either_side
          self.y_vel = new_y - y if new_y
      end
    end

    move
  end

  def look_ahead_for_support_both_sides
    left_support, right_support = possible_sources_of_support

    # Find the highest (if dropping) or lowest (if rising) height on
    # the left that matches with something on the right
    left_heights = left_support.sort
    find_match_on_right = proc do |left_y|
      return left_y if right_support.include?(left_y)
    end

    if y_vel > 0 # dropping
      left_heights.each(&find_match_on_right)
    else # rising
      left_heights.reverse_each(&find_match_on_right)
    end

    nil
  end

  def look_ahead_for_support_either_side
    left_support, right_support = possible_sources_of_support

    # Find the highest (if dropping) or lowest (if rising) height on
    # either side
    all_heights = left_support + right_support
    (y_vel > 0) ? all_heights.min : all_heights.max
  end

  # Sources of support must intersect with the points next
  # to us, and be:
  # - Level with our lower edge, if dropping
  # - A point above our upper edge, if rising
  #
  # This just returns the heights at which we might find support
  def possible_sources_of_support
    target_height = if y_vel > 0 # dropping
      y + HEIGHT - 1
    else # rising
      y - 1
    end

    left_support = opaque(space.entities_at_point(x - 1, target_height)).collect(&:y)
    right_support = opaque(space.entities_at_point(x + WIDTH, target_height)).collect(&:y)

    # Filter out heights we aren't going to reach this tick with
    # our current velocity
    not_too_far = lambda {|its_y| (its_y - y).abs <= y_vel.abs }
    [left_support.find_all(&not_too_far), right_support.find_all(&not_too_far)]
  end

  def harmed_by(other, damage=1)
    self.hp -= damage
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

  def to_s; "#{super} (#{@hp} HP)"; end
end

end
