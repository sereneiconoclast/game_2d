require 'entity'
require 'gosu'
require 'zorder'

class NPC < Entity
  def initialize(space, x, y, a = 0, x_vel = 0, y_vel = 0)
    super
  end

  # Primitive gravity: Accelerate downward if there are no entities underneath
  def update
    accelerate(0, 1) if empty_underneath?
    super
  end

  # Sleep if any cells underneath are occupied and we're not moving
  def sleep_now?
    self.x_vel == 0 && self.y_vel == 0 && !empty_underneath?
  end

  def to_s
    "NPC (#{registry_id_safe}) at #{x}x#{y}"
  end

  def as_json
    super().merge( :class => 'NPC' )
  end

  def image_filename; "media/tele.gif"; end
end
