require 'game_2d/complex_move'
require 'game_2d/entity_constants'

module Move

class LineUp < ComplexMove
  include EntityConstants

  def initialize(actor=nil)
    super
    if actor # not supplied during deserialization
      @with_id = actor.space.nearest_to(
        actor.underfoot, actor.cx, actor.cy
      ).nullsafe_registry_id
    end
  end

  def on_completion(actor)
    actor.x_vel = actor.y_vel = 0
  end

  def update(actor)
    return false unless @with_id
    # Abort if the aligned-with object gets destroyed
    return false unless with = actor.space[@with_id]

    case actor.a
      when 0, 180 then line_up_x(actor, with)
      when 90, 270 then line_up_y(actor, with)
      else false
    end
  end

  def line_up_x(actor, with)
    actor.instance_exec(self) do |cm|
      delta = with.x - x
      return false if delta.zero?
      delta = Entity.constrain_velocity(delta, PIXEL_WIDTH)
      self.x_vel, self.y_vel = delta, 0
      # move returns false: it failed somehow
      move
    end
  end

  def line_up_y(actor, with)
    actor.instance_exec(self) do |cm|
      delta = with.y - y
      return false if delta.zero?
      delta = Entity.constrain_velocity(delta, PIXEL_WIDTH)
      self.x_vel, self.y_vel = 0, delta
      # move returns false: it failed somehow
      move
    end
  end

  def all_state
    super.push @with_id
  end
  def as_json
    super.merge! :with => @with_id
  end
  def update_from_json(json)
    @with_id = json[:with].to_sym if json[:with]
    super
  end
  def to_s
    "LineUp[#{@with_id}]"
  end

end

end
