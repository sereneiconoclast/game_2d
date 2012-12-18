require 'rubygems'
require 'chipmunk_utilities'

# Common code between the server and client for maintaining the world.
# This is a bounded space (walls on all sides).
#
# Maintains a registry of objects.  All game objects must have a registry_id
# set before they will be accepted.  They must also offer a body and a shape,
# which will be added.
#
# Also maintains a list of objects due to be deleted, to avoid removing them
# at the wrong time (during collision processing).

GRAVITY = 10.0

class GameSpace
  attr_reader :registry, :players, :npcs, :width, :height

  def initialize(delta_t)
    # Extending CP::Space seems to be a bad thing to do (SEGV).
    # So let's fake it
    @real_space = CP::Space.new

    # Time increment over which to apply a physics "step" ("delta t")
    @dt = delta_t

    @real_space.gravity = CP::Vec2.new(0.0, GRAVITY)

    @registry = {}

    # I create a @doomed array because we cannot remove either Shapes or Bodies
    # from Space within a collision closure, rather, we have to wait till the closure
    # is through executing, then we can remove the Shapes and Bodies
    # In this case, the Shapes and the Bodies they own are removed in the Gosu::Window.update phase
    # by iterating over the @doomed array
    @doomed = []

    @players = Array.new
    @npcs = Array.new
  end

  def method_missing(sym, *args, &blk)
    @real_space.send sym, *args, &blk
  end

  def establish_world(width, height)
    puts "World is #{width}x#{height}"
    @width, @height = width, height

    add_bounding_walls
  end

  def add_bounding_walls
    add_bounding_wall(width / 2, 0.0, width, 0.0)     # top
    add_bounding_wall(width / 2, height, width, 0.0)  # bottom
    add_bounding_wall(0.0, height / 2, 0.0, height)   # left
    add_bounding_wall(width, height / 2, 0.0, height) # right
  end

  def add_bounding_wall(x_pos, y_pos, width, height)
    wall = CP::Body.new_static
    wall.p = CP::Vec2.new(x_pos, y_pos)
    wall.v = CP::Vec2.new(0.0, 0.0)
    wall.v_limit = 0.0 # max velocity (never move)
    shape = CP::Shape::Segment.new(wall,
      CP::Vec2.new(-0.5 * width, -0.5 * height),
      CP::Vec2.new(0.5 * width, 0.5 * height),
      1.0) # thickness
    shape.collision_type = :wall
    shape.e = 0.99 # elasticity (bounce)
    @real_space.add_body(wall)
    @real_space.add_shape(shape)
  end

  # Retrieve object by ID
  def [](registry_id)
    @registry[registry_id]
  end

  # List of objects by type
  def object_list(obj)
    case obj
    when Player then @players
    when NPC then @npcs
    else raise "Unknown object type: #{obj} (#{obj.class})"
    end
  end

  # Override to be informed when trying to add an object that
  # we already have (registry ID clash)
  def fire_duplicate_id(old_object, new_object); end

  # Add an object
  def <<(obj)
    reg_id = obj.registry_id
    if old = self[reg_id]
      fire_duplicate_id(old, obj)
      old
    else
      @registry[reg_id] = obj
      object_list(obj) << obj
      @real_space.add_body(obj.body)
      @real_space.add_shape(obj.shape)
      obj
    end
  end

  # Doom an object (mark it to be deleted but don't remove it yet)
  def doom(obj); @doomed << obj; end

  def doomed?(obj); @doomed.include?(obj); end

  # Override to be informed when trying to purge an object that
  # turns out not to exist
  def fire_object_not_found(object); end

  def purge_doomed_objects
    @doomed.each do |object|
      if @registry.delete object.registry_id
        object_list(object).delete object

        @real_space.remove_body(object.body)
        @real_space.remove_shape(object.shape)
      else
        fire_object_not_found(object)
      end
    end
    @doomed.clear
  end

  def dequeue_player_moves
    @players.each &:dequeue_move
  end

  def update
    purge_doomed_objects

    # Process commands by all players
    @players.each &:execute_move

    # Perform the step over @dt period of time
    # For best performance @dt should remain consistent for the game
    @real_space.step(@dt)
  end

  # Assertion.  Used server-side only
  def check_for_registry_leaks
    expected = @players.size + @npcs.size
    actual = @registry.size
    if expected != actual
      raise "We have #{expected} game objects, #{actual} in registry (delta: #{actual - expected})"
    end
  end

  # Used client-side only.  Determine an appropriate camera position,
  # given the specified window size, and preferring that the specified object
  # be in the center
  def good_camera_position_for(obj, screen_width, screen_height)
    # Given plenty of room, put the object in the middle of the screen
    # If doing so would expose the area outside the world, move the camera just enough
    # to avoid that
    # If the world is smaller than the window, center it

    camera_x = if screen_width > @width
      (@width - screen_width) / 2 # negative
    else
      [[obj.body.p.x - screen_width/2, @width - screen_width].min, 0].max
    end
    camera_y = if screen_height > @height
      (@height - screen_height) / 2 # negative
    else
      [[obj.body.p.y - screen_height/2, @height - screen_height].min, 0].max
    end

    [ camera_x, camera_y ]
  end
end
