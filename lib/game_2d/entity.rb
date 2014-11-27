require 'facets/string/pathize'
require 'facets/kernel/constant'
require 'game_2d/registerable'
require 'game_2d/serializable'
require 'game_2d/entity_constants'
require 'game_2d/transparency'

class NilClass
  # Ignore this
  def wake!; end
end

class Entity
  include EntityConstants

  module ClassMethods
    include EntityConstants
    # Left-most cell X position occupied
    def left_cell_x_at(x); x / WIDTH; end

    # Right-most cell X position occupied
    # If we're exactly within a column (@x is an exact multiple of WIDTH),
    # then this equals left_cell_x.  Otherwise, it's one higher
    def right_cell_x_at(x); (x + WIDTH - 1) / WIDTH; end

    # Top-most cell Y position occupied
    def top_cell_y_at(y); y / HEIGHT; end

    # Bottom-most cell Y position occupied
    def bottom_cell_y_at(y); (y + HEIGHT - 1) / HEIGHT; end

    # Velocity is constrained to the range -MAX_VELOCITY .. MAX_VELOCITY
    def constrain_velocity(vel)
      [[vel, MAX_VELOCITY].min, -MAX_VELOCITY].max
    end
  end
  include ClassMethods
  extend ClassMethods

  include Serializable
  include Registerable
  include Transparency

  # X and Y position of the top-left corner
  attr_accessor :x, :y, :moving, :space

  attr_reader :a, :x_vel, :y_vel

  # space: the game space
  # x, y: position in sub-pixels of the upper-left corner
  # a: angle, with 0 = up, 90 = right
  # x_vel, y_vel: velocity in sub-pixels
  def initialize(x = 0, y = 0, a = 0, x_vel = 0, y_vel = 0)
    @x, @y, self.a = x, y, a
    self.x_vel, self.y_vel = x_vel, y_vel
    @moving = true
    @grabbed = false
  end

  def a=(angle); @a = angle % 360; end

  def x_vel=(xv)
    @x_vel = constrain_velocity xv
  end
  def y_vel=(yv)
    @y_vel = constrain_velocity yv
  end

  # True if we need to update this entity
  def moving?; @moving; end

  def doomed?; @space.doomed?(self); end

  # True if this entity can go to sleep now
  # Only called if update() fails to produce any motion
  # Default: Sleep if we're not moving and not falling
  def sleep_now?
    self.x_vel == 0 && self.y_vel == 0 && !should_fall?
  end

  def should_fall?
    raise "should_fall? undefined"
  end

  # Notify this entity that it must take action
  def wake!
    @moving = true
  end

  # Entity is under direct control by a player
  # This is transitory state (not persisted or copied)
  def grab!; @grabbed = true; end
  def release!; @grabbed = false; end
  def grabbed?; @grabbed; end

  # Give this entity a chance to perform clean-up upon destruction
  def destroy!; end

  # X positions near this entity's
  # Position in pixels of the upper-left corner
  def pixel_x; @x / PIXEL_WIDTH; end
  def pixel_y; @y / PIXEL_WIDTH; end

  def left_cell_x(x = @x); left_cell_x_at(x); end
  def right_cell_x(x = @x); right_cell_x_at(x); end
  def top_cell_y(y = @y); top_cell_y_at(y); end
  def bottom_cell_y(y = @y); bottom_cell_y_at(y); end

  # Returns an array of one, two, or four cell-coordinate tuples
  # E.g. [[4, 5], [4, 6], [5, 5], [5, 6]]
  def occupied_cells(x = @x, y = @y)
    x_array = (left_cell_x(x) .. right_cell_x(x)).to_a
    y_array = (top_cell_y(y) .. bottom_cell_y(y)).to_a
    x_array.product(y_array)
  end

  # Apply acceleration
  def accelerate(x_accel, y_accel)
    self.x_vel = @x_vel + x_accel
    self.y_vel = @y_vel + y_accel
  end

  def opaque(others)
    others.delete_if {|obj| obj.equal?(self) || transparent?(self, obj)}
  end

  # Wrapper around @space.entities_overlapping
  # Allows us to remove any entities that are transparent
  # to us
  def entities_obstructing(new_x, new_y)
    fail "No @space set!" unless @space
    opaque(@space.entities_overlapping(new_x, new_y))
  end

  # Process one tick of motion, horizontally only
  def move_x
    return if doomed?
    return if @x_vel.zero?
    new_x = @x + @x_vel
    impacts = entities_obstructing(new_x, @y)
    if impacts.empty?
      @x = new_x
      return
    end
    @x = if @x_vel > 0 # moving right
      # X position of leftmost candidate(s)
      impact_at_x = impacts.collect(&:x).min
      impacts.delete_if {|e| e.x > impact_at_x }
      impact_at_x - WIDTH
    else # moving left
      # X position of rightmost candidate(s)
      impact_at_x = impacts.collect(&:x).max
      impacts.delete_if {|e| e.x < impact_at_x }
      impact_at_x + WIDTH
    end
    self.x_vel = 0
    i_hit(impacts)
  end

  # Process one tick of motion, vertically only
  def move_y
    return if doomed?
    return if @y_vel.zero?
    new_y = @y + @y_vel
    impacts = entities_obstructing(@x, new_y)
    if impacts.empty?
      @y = new_y
      return
    end
    @y = if @y_vel > 0 # moving down
      # Y position of highest candidate(s)
      impact_at_y = impacts.collect(&:y).min
      impacts.delete_if {|e| e.y > impact_at_y }
      impact_at_y - HEIGHT
    else # moving up
      # Y position of lowest candidate(s)
      impact_at_y = impacts.collect(&:y).max
      impacts.delete_if {|e| e.y < impact_at_y }
      impact_at_y + HEIGHT
    end
    self.y_vel = 0
    i_hit(impacts)
  end

  # Process one tick of motion.  Only called when moving? is true
  def move
    # Force evaluation of both update_x and update_y (no short-circuit)
    # If we're moving faster horizontally, do that first
    # Otherwise do the vertical move first
    moved = @space.process_moving_entity(self) do
      if @x_vel.abs > @y_vel.abs then move_x; move_y
      else move_y; move_x
      end
    end

    # Didn't move?  Might be time to go to sleep
    @moving = false if !moved && sleep_now?

    moved
  end

  # Handle any behavior specific to this entity
  # Default: Accelerate downward if the subclass says we should fall
  def update
    accelerate(0, 1) if should_fall?
    move
  end

  # Update position/velocity/angle data, and tell the space about it
  def warp(x, y, x_vel, y_vel, angle=self.a, moving=@moving)
    blk = proc do
      @x, @y, self.x_vel, self.y_vel, self.a, @moving =
        x, y, x_vel, y_vel, angle, moving
    end
    if @space
      @space.process_moving_entity(self, &blk)
    else
      blk.call
    end
  end

  def i_hit(other)
    # TODO
    puts "#{self} hit #{other.inspect}"
  end

  def harmed_by(other); end

  # Return any entities adjacent to this one in the specified direction
  def next_to(angle, x=@x, y=@y)
    points = case angle % 360
    when 0 then
      [[x, y - 1], [x + WIDTH - 1, y - 1]]
    when 90 then
      [[x + WIDTH, y], [x + WIDTH, y + HEIGHT - 1]]
    when 180 then
      [[x, y + HEIGHT], [x + WIDTH - 1, y + HEIGHT]]
    when 270 then
      [[x - 1, y], [x - 1, y + HEIGHT - 1]]
    else puts "Trig unimplemented"; []
    end
    @space.entities_at_points(points)
  end

  def empty_underneath?; opaque(next_to(180)).empty?; end
  def empty_on_left?; opaque(next_to(270)).empty?; end
  def empty_on_right?; opaque(next_to(90)).empty?; end
  def empty_above?; opaque(next_to(0)).empty?; end

  def angle_to_vector(angle, amplitude=1)
    case angle % 360
    when 0 then [0, -amplitude]
    when 90 then [amplitude, 0]
    when 180 then [0, amplitude]
    when 270 then [-amplitude, 0]
    else raise "Trig unimplemented"
    end
  end

  # Convert x/y to an angle
  def vector_to_angle(x_vel=@x_vel, y_vel=@y_vel)
    if x_vel == 0 && y_vel == 0
      return puts "Zero velocity, no angle"
    end
    if x_vel != 0 && y_vel != 0
      return puts "Diagonal velocity (#{x_vel}x#{y_vel}), no angle"
    end

    if x_vel.zero?
      (y_vel > 0) ? 180 : 0
    else
      (x_vel > 0) ? 90 : 270
    end
  end

  # Given a vector with a diagonal, drop the smaller component, returning a
  # vector that is strictly either horizontal or vertical.
  def drop_diagonal(x_vel, y_vel)
    (y_vel.abs > x_vel.abs) ? [0, y_vel] : [x_vel, 0]
  end

  # Is the other entity basically above us, below us, or on the left or the
  # right?  Returns the angle we should face if we want to face that entity.
  def direction_to(other_x, other_y)
    vector_to_angle(*drop_diagonal(other_x - @x, other_y - @y))
  end

  # Given our current position and velocity (and only if our velocity is not
  # on a diagonal), are we about to move past the entity at the specified
  # coordinates?  If so, returns:
  #
  # 1) The X/Y position of the empty space just past the entity.  Assuming the
  # other entity is adjacent to us, this spot touches corners with the other
  # entity.
  #
  # 2) How far we'd go to reach that point.
  #
  # 3) How far past that spot we would go.
  #
  # 4) Which way we'd have to turn (delta angle) if moving around the other
  # entity.  Either +90 or -90.
  def going_past_entity(other_x, other_y)
    return if @x_vel == 0 && @y_vel == 0
    return if @x_vel != 0 && @y_vel != 0

    if @x_vel.zero?
      # Moving vertically.  Find target height
      y_pos = (@y_vel > 0) ? other_y + HEIGHT : other_y - HEIGHT
      distance = (@y - y_pos).abs
      overshoot = @y_vel.abs - distance
      turn = if @y_vel > 0
        # Going down: Turn left if it's on our right
        direction_to(other_x, other_y) == 90 ? -90 : 90
      else
        # Going up: Turn right if it's on our right
        direction_to(other_x, other_y) == 90 ? 90 : -90
      end
      return [[@x, y_pos], distance, overshoot, turn] if overshoot >= 0
    else
      # Moving horizontally.  Find target column
      x_pos = (@x_vel > 0) ? other_x + WIDTH : other_x - WIDTH
      distance = (@x - x_pos).abs
      overshoot = @x_vel.abs - distance
      turn = if @x_vel > 0
        # Going right: Turn right if it's below us
        direction_to(other_x, other_y) == 180 ? 90 : -90
      else
        # Going left: Turn left if it's below us
        direction_to(other_x, other_y) == 180 ? -90 : 90
      end
      return [[x_pos, @y], distance, overshoot, turn] if overshoot >= 0
    end
  end

  def as_json
    Serializable.as_json(self).merge!(
      :class => self.class.to_s,
      :registry_id => registry_id,
      :position => [ self.x, self.y ],
      :velocity => [ self.x_vel, self.y_vel ],
      :angle => self.a,
      :moving => self.moving?
    )
  end

  def update_from_json(json)
    new_x, new_y = json[:position]
    new_x_vel, new_y_vel = json[:velocity]
    new_angle = json[:angle]
    new_moving = json[:moving]

    warp(new_x, new_y, new_x_vel, new_y_vel, new_angle, new_moving)
    self
  end

  def image_filename
    raise "No image filename defined"
  end

  def draw_zorder; ZOrder::Objects end

  def draw(window)
    anim = window.animation[window.media(image_filename)]
    img = anim[Gosu::milliseconds / 100 % anim.size]
    # Entity's pixel_x/pixel_y is the location of the upper-left corner
    # draw_rot wants us to specify the point around which rotation occurs
    # That should be the center
    img.draw_rot(
      self.pixel_x + CELL_WIDTH_IN_PIXELS / 2,
      self.pixel_y + CELL_WIDTH_IN_PIXELS / 2,
      draw_zorder, self.a)
    # 0.5, 0.5, # rotate around the center
    # 1, 1, # scaling factor
    # @color, # modify color
    # :add) # draw additively
  end

  def to_s
    "#{self.class} (#{registry_id_safe}) at #{x}x#{y}"
  end

  def all_state
    [registry_id_safe, @x, @y, @a, @x_vel, @y_vel, @moving]
  end
end
