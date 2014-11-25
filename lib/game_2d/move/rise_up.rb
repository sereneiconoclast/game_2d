require 'game_2d/complex_move'
require 'game_2d/entity_constants'

module Move

class RiseUp < ComplexMove
  include EntityConstants

  # Valid stages: :center, :rise, :reset
  # Distance is how much further we need to go
  # (in pixels) in stage :rise
  attr_accessor :stage, :distance
  def initialize(actor=nil)
    super
    @stage = :center
  end

  def on_completion(actor)
    actor.instance_exec { @x_vel = @y_vel = 0 }
  end

  def update(actor)
    # It's convenient to set 'self' to the Player
    # object, here
    actor.instance_exec(self) do |cm|
      # Abort if the build_block gets destroyed
      blok = build_block
      return false unless blok

      start_x, start_y = blok.x, blok.y
      case cm.stage
      when :center, :reset
        if x == start_x && y == start_y
          # If we're in reset, we're all done
          return false if cm.stage == :reset

          # Establish our velocity for :rise
          cm.stage = :rise
          @x_vel, @y_vel = angle_to_vector(a, PIXEL_WIDTH)
          cm.distance = CELL_WIDTH_IN_PIXELS
          return cm.update(self)
        end
        @x_vel = [[start_x - x, -PIXEL_WIDTH].max, PIXEL_WIDTH].min
        @y_vel = [[start_y - y, -PIXEL_WIDTH].max, PIXEL_WIDTH].min
        # move returns false: it failed somehow
        return move
      when :rise
        # Success
        return false if cm.distance.zero?

        cm.distance -= 1
        # move fails? Go to :reset
        move || (cm.stage = :reset)
        return true
      end
    end
  end

  def all_state
    super.push @stage, @distance
  end
  def as_json
    super.merge! :stage => @stage,
      :distance => @distance
  end
  def update_from_json(json)
    self.stage = json[:stage].to_sym
    self.distance = json[:distance]
    super
  end
  def to_s
    "RiseUp[#{stage}, #{distance} to go]"
  end

end

end
