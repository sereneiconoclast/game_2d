require 'game_2d/entity'

class Entity

class Hole < Entity
  def should_fall?; false; end

  def apply_gravity_to?(entity)
    distance = space.distance_between(cx, cy, entity.cx, entity.cy)
    entity.harmed_by(self, (400 - distance).ceil) if distance < 400
    force = 10000000.0 / (distance**2)
    return true if force > 200.0
    return false if force < 1.0
    # We could use trig here -- but we have a shortcut.
    # We know the X/Y proportions of the force must be
    # the same as the X/Y proportions of the distance.
    delta_x = cx - entity.cx
    delta_y = cy - entity.cy
    force_x = force * (delta_x / distance)
    force_y = force * (delta_y / distance)
    entity.accelerate(force_x.truncate, force_y.truncate)
    true
  end

  def update; end

  def image_filename; "hole.png"; end

  def draw_zorder; ZOrder::Teleporter end
end

end
