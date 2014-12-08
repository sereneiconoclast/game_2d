require 'game_2d/entity/owned_entity'

class Entity

# Slime is like a lemming(tm): it either falls, or it walks left
# or right until forced to reverse direction
#
# As it comes into contact with other entities, it gradually
# increments its slime_count, until it maxes out.  Then it harms
# whatever it just touched, and resets the count
class Slime < Entity
  MAX_HP = 8
  MAX_SPEED = 18
  SLEEP_AMOUNT = 180
  MAX_SLIME_COUNT = 100

  attr_reader :hp, :sleep_count, :slime_count

  def initialize
    super
    self.a = 270
    @hp, @sleep_count, @slime_count = MAX_HP, 0, 0
  end

  def hp=(p); @hp = [[p, MAX_HP].min, 0].max; end

  def all_state; super.push(hp, sleep_count, slime_count); end
  def as_json
    super.merge(
      :hp => hp,
      :sleep_count => @sleep_count,
      :slime_count => @slime_count
    )
  end

  def update_from_json(json)
    self.hp = json[:hp] if json[:hp]
    @sleep_count = json[:sleep_count] if json[:sleep_count]
    @slime_count = json[:slime_count] if json[:slime_count]
    super
  end

  def should_fall?; empty_underneath?; end

  def trapped?; !(empty_on_left? || empty_on_right?); end

  def sleep_now?; false; end

  def update
    if should_fall?
      self.x_vel = @sleep_count = 0
      space.fall(self)
      move
    elsif @sleep_count.zero?
      slime_them(beneath, 1)
      if trapped?
        self.a += 180
        slime_them((a == 270) ? on_left : on_right, 1)
        @sleep_count = SLEEP_AMOUNT
      else
        self.y_vel = 0
        accelerate((a == 270) ? -1 : 1, nil, MAX_SPEED)
        self.a += 180 unless move
      end
    else
      @sleep_count -= 1
    end
  end

  def i_hit(others, velocity)
    slime_them(others, velocity)
  end

  def slime_them(others, increment)
    @slime_count += increment
    if @slime_count > MAX_SLIME_COUNT
      @slime_count -= MAX_SLIME_COUNT
      others.each {|o| o.harmed_by(self) unless o.is_a? Slime}
    end
  end

  def harmed_by(other, damage=1)
    self.hp -= damage
    @space.doom(self) if hp <= 0
  end

  def image_filename; "slime.png"; end

  def draw(window)
    img = draw_image(draw_animation(window))

    # Default image faces left
    # We don't rotate the slime; we just flip it horizontally
    img.draw(
      self.pixel_x + (a == 90 ? CELL_WIDTH_IN_PIXELS : 0), self.pixel_y, draw_zorder,
      (a == 90 ? -1 : 1) # X scaling factor
    )
    # 0.5, 0.5, # rotate around the center
    # 1, 1, # scaling factor
    # @color, # modify color
    # :add) # draw additively
  end

  def to_s; "#{super} (#{@hp} HP)"; end
end

end
