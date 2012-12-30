require 'registerable'

class NilClass
  # Ignore this
  def wake!; end
end

class Entity
  include Registerable

  # All our drawings are 40x40
  CELL_WIDTH_IN_PIXELS = 40

  # We track entities at a resolution higher than pixels, called "subpixels"
  # This is the smallest detectable motion, 1 / PIXEL_WIDTH of a pixel
  PIXEL_WIDTH = 10

  # The dimensions of a cell, equals the dimensions of an entity
  WIDTH = HEIGHT = CELL_WIDTH_IN_PIXELS * PIXEL_WIDTH

  # Maximum velocity is a full cell per tick, which is a lot
  MAX_VELOCITY = WIDTH

  # X and Y position of the top-left corner
  attr_accessor :x, :y, :a, :x_vel, :y_vel, :moving

  attr_reader :space

  # space: the game space
  # x, y: position in sub-pixels of the upper-left corner
  # a: angle, with 0 = up, 90 = right
  # x_vel, y_vel: velocity in sub-pixels
  def initialize(space, x, y, a = 0, x_vel = 0, y_vel = 0)
    @space, @x, @y, @a, @x_vel, @y_vel = space, x, y, a, x_vel, y_vel
    @moving = true
  end

  # True if we need to update this entity
  def moving?; @moving; end

  # True if this entity can go to sleep now
  # Only called if update() fails to produce any motion
  def sleep_now?
    raise "Unimplemented on #{self.class}: sleep_now?()"
  end

  # Notify this entity that it must take action
  def wake!
    @moving = true
  end

  # X positions near this entity's
  # Position in pixels of the upper-left corner
  def pixel_x; @x / PIXEL_WIDTH; end
  def pixel_y; @y / PIXEL_WIDTH; end

  # Left-most cell X position occupied
  def self.left_cell_x_at(x); x / WIDTH; end
  # TODO: Find a more elegant way to call class methods in Ruby...
  def left_cell_x(x = @x); self.class.left_cell_x_at(x); end

  # Right-most cell X position occupied
  # If we're exactly within a column (@x is an exact multiple of WIDTH),
  # then this equals left_cell_x.  Otherwise, it's one higher
  def self.right_cell_x_at(x); (x + WIDTH - 1) / WIDTH; end
  def right_cell_x(x = @x); self.class.right_cell_x_at(x); end

  # Top-most cell Y position occupied
  def self.top_cell_y_at(y); y / HEIGHT; end
  def top_cell_y(y = @y); self.class.top_cell_y_at(y); end

  # Bottom-most cell Y position occupied
  def self.bottom_cell_y_at(y); (y + HEIGHT - 1) / HEIGHT; end
  def bottom_cell_y(y = @y); self.class.bottom_cell_y_at(y); end

  # Returns an array of one, two, or four cell-coordinate tuples
  # E.g. [[4, 5], [4, 6], [5, 5], [5, 6]]
  def occupied_cells(x = @x, y = @y)
    x_array = (left_cell_x(x) .. right_cell_x(x)).to_a
    y_array = (top_cell_y(y) .. bottom_cell_y(y)).to_a
    x_array.product(y_array)
  end

  # Apply acceleration, limited to the range -MAX_VELOCITY .. MAX_VELOCITY
  def accelerate(x_accel, y_accel)
    @x_vel = [[@x_vel + x_accel, MAX_VELOCITY].min, -MAX_VELOCITY].max
    @y_vel = [[@y_vel + y_accel, MAX_VELOCITY].min, -MAX_VELOCITY].max
  end

  # Process one tick of motion, horizontally only
  def update_x
    return if @x_vel.zero?
    new_x = @x + @x_vel
    impacts = @space.entities_overlapping(new_x, @y).delete(self)
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
    @x_vel = 0
    impacts.each {|other| other.impacted_by(self) }
  end

  # Process one tick of motion, vertically only
  def update_y
    return if @y_vel.zero?
    new_y = @y + @y_vel
    impacts = @space.entities_overlapping(@x, new_y).delete(self)
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
    @y_vel = 0
    impacts.each {|other| other.impacted_by(self) }
  end

  # Process one tick of motion.  Only called when moving? is true
  def update
    # Force evaluation of both update_x and update_y (no short-circuit)
    # If we're moving faster horizontally, do that first
    # Otherwise do the vertical move first
    moved = @space.process_moving_entity(self) do
      if @x_vel.abs > @y_vel.abs
        update_x
        update_y
      else
        update_y
        update_x
      end
    end

    # Didn't move?  Might be time to go to sleep
    if !moved && sleep_now?
      puts "#{self} going to sleep..."
      @moving = false
    end
  end

  # Update position/velocity/angle data, and tell the space about it
  def warp(x, y, x_vel, y_vel, angle=self.a, moving=@moving)
    @space.process_moving_entity(self) do
      @x, @y, @x_vel, @y_vel, @a, @moving =
        x, y, x_vel, y_vel, angle, moving
    end
  end

  def impacted_by(other)
    # TODO
    puts "#{self} impacted by #{other}"
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  def as_json
    {
      :class => self.class.to_s,
      :registry_id => registry_id,
      :position => [ self.x, self.y ],
      :velocity => [ self.x_vel, self.y_vel ],
      :angle => self.a,
      :moving => self.moving?,
    }
  end

  def update_from_json(json)
    new_x, new_y = json['position']
    new_x_vel, new_y_vel = json['velocity']
    new_angle = json['angle']
    new_moving = json['moving']

    warp(new_x, new_y, new_x_vel, new_y_vel, new_angle, new_moving)
  end

  def self.from_json(space, json)
    clazz = self.class.const_get(json['class'], true)
    # TODO: This will only work for NPC, until we get the constructors
    # for NPC/Player in sync
    entity = clazz.new(space, 0, 0)
    entity.registry_id = json['registry_id']
    entity.update_from_json(json)
    entity
  end
end