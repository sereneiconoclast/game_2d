require 'set'
require 'wall'

# Common code between the server and client for maintaining the world.
# This is a bounded space (walls on all sides).
#
# Maintains a registry of entities.  All game entities must have a registry_id
# set before they will be accepted.
#
# Also maintains a list of entities due to be deleted, to avoid removing them
# at the wrong time (during collision processing).


# The behavior I want from sets-of-sets is to consider them all unique objects.
# I'm using them to represent cells in the game grid, and want to be able to
# say "Subtract this set of cells from that set".  Treating Sets as equal if
# their contents are equal defeats this purpose.
#
# It's also handy if each Set knows where it lives in the grid.

class Cell < Set
  def ==(other); object_id == other.object_id; end
  def eql?(other); object_id == other.object_id; end

  def initialize(cell_x, cell_y)
    super()
    @cell_x, @cell_y = cell_x, cell_y
  end
  def to_s; "(#{@cell_x}, #{@cell_y}) [#{to_a.join(', ')}]"; end
end


class GameSpace
  attr_reader :registry, :players, :npcs, :cell_width, :cell_height
  attr_accessor :storage

  def initialize
    @grid = @storage = nil

    @registry = {}

    # I create a @doomed array so we can remove entities after all collisions
    # have been processed, to avoid confusion
    @doomed = []

    @players = Array.new
    @npcs = Array.new
  end

  # Width and height, measured in cells
  # TODO: This may now be safe to fold into initialize()
  def establish_world(cell_width, cell_height)
    puts "World is #{cell_width}x#{cell_height} cells"
    @cell_width, @cell_height = cell_width, cell_height

    # Outer array is X-indexed; inner arrays are Y-indexed
    # Therefore you can look up @grid[cell_x][cell_y] ...
    # However, for convenience, we make the grid two cells wider, two cells
    # taller.  Then we can populate the edge with Wall instances, and treat (0,
    # 0) as a usable coordinate.  (-1, -1) contains a Wall, for example.  The
    # at(), put(), and cut() methods do the translation, so only they should
    # access @grid directly
    @grid = Array.new(cell_width + 2) do |cy|
      Array.new(cell_height + 2) do |cx|
        Cell.new(cx-1, cy-1)
      end
    end

    # Top and bottom, including corners
    (-1 .. cell_width).each do |cell_x|
      put(cell_x, -1, Wall.new(self, cell_x, -1))                   # top
      put(cell_x, cell_height, Wall.new(self, cell_x, cell_height)) # bottom
    end

    # Left and right, skipping corners
    (0 .. cell_height - 1).each do |cell_y|
      put(-1, cell_y, Wall.new(self, -1, cell_y))                 # left
      put(cell_width, cell_y, Wall.new(self, cell_width, cell_y)) # right
    end

    self
  end

  def self.load(storage)
    cell_width, cell_height = storage['cell_width'], storage['cell_height']
    space = GameSpace.new.establish_world(cell_width, cell_height)
    space.storage = storage
    space.load
  end

  def save
    @storage['cell_width'], @storage['cell_height'] = @cell_width, @cell_height
    @storage['npcs'] = @npcs
    @storage.save
  end

  # TODO: Handle this while server is running and players are connected
  # TODO: Handle resizing the space
  def load
    @storage['npcs'].each do |json|
      puts "Loading #{json.inspect}"
      self << Entity.from_json(self, json)
    end
    self
  end

  def pixel_width; @cell_width * Entity::CELL_WIDTH_IN_PIXELS; end
  def pixel_height; @cell_height * Entity::CELL_WIDTH_IN_PIXELS; end
  def width; @cell_width * Entity::WIDTH; end
  def height; @cell_height * Entity::HEIGHT; end

  # Retrieve entity by ID
  def [](registry_id)
    @registry[registry_id]
  end

  # We can safely look up cell_x == -1, cell_x == @cell_width, cell_y == -1,
  # and/or cell_y == @cell_height -- any of these returns a Wall instance
  def assert_ok_coords(cell_x, cell_y)
    raise "Illegal coordinate #{cell_x}x#{cell_y}" if (
      cell_x < -1 ||
      cell_y < -1 ||
      cell_x > @cell_width ||
      cell_y > @cell_height
    )
  end

  # Retrieve set of entities falling (partly) within cell coordinates,
  # zero-based
  def at(cell_x, cell_y)
    assert_ok_coords(cell_x, cell_y)
    @grid[cell_x - 1][cell_y - 1]
  end

  # Low-level adder
  def put(cell_x, cell_y, entity)
    assert_ok_coords(cell_x, cell_y)
    @grid[cell_x - 1][cell_y - 1] << entity
  end

  # Low-level remover
  def cut(cell_x, cell_y, entity)
    assert_ok_coords(cell_x, cell_y)
    @grid[cell_x - 1][cell_y - 1].delete entity
  end

  # Translate a subpixel point (X, Y) to a cell coordinate (cell_x, cell_y)
  def cell_at_point(x, y)
    [x / Entity::WIDTH, y / Entity::HEIGHT ]
  end

  # Translate multiple subpixel points (X, Y) to a set of cell coordinates
  # (cell_x, cell_y)
  def cells_at_points(coords)
    coords.collect {|x, y| cell_at_point(x, y) }.to_set
  end

  # Given the (X, Y) position of a theoretical entity, return the list of all
  # the coordinates of its corners
  def corner_points_of_entity(x, y)
    [
      [x, y],
      [x + Entity::WIDTH - 1, y],
      [x, y + Entity::HEIGHT - 1],
      [x + Entity::WIDTH - 1, y + Entity::HEIGHT - 1],
    ]
  end

  # Return the entity (if any) at a subpixel point (X, Y)
  def entity_at_point(x, y)
    all = at(*cell_at_point(x, y)).find_all do |e|
      e.x <= x && e.x > (x - Entity::WIDTH) &&
      e.y <= y && e.y > (y - Entity::HEIGHT)
    end
    raise "More than one entity at #{x}x#{y}: #{all.inspect}" if all.size > 1
    all.first
  end

  # Accepts a collection of (x, y)
  def entities_at_points(coords)
    coords.collect {|x, y| entity_at_point(x, y) }.compact.to_set
  end

  # The set of entities that may be affected by an entity moving to (or from)
  # the specified (x, y) coordinates
  # This includes the coordinates of eight points just beyond the entity's
  # borders
  def entities_bordering_entity_at(x, y)
    r = x + Entity::WIDTH - 1
    b = y + Entity::HEIGHT - 1
    entities_at_points([
      [x - 1, y], [x, y - 1], # upper-left corner
      [r + 1, y], [r, y - 1], # upper-right corner
      [x - 1, b], [x, b + 1], # lower-left corner
      [r + 1, b], [r, b + 1], # lower-right corner
    ])
  end

  # Retrieve set of entities that overlap with a theoretical entity created at
  # position [x, y] (in subpixels)
  def entities_overlapping(x, y)
    entities_at_points(corner_points_of_entity(x, y))
  end

  # Retrieve list of cells (sets) that overlap with a theoretical entity
  # at position [x, y] (in subpixels).
  def cells_overlapping(x, y)
    cells_at_points(corner_points_of_entity(x, y)).collect {|cx, cy| at(cx, cy) }
  end

  # Add the entity to the grid
  def add_entity_to_grid(entity)
    cells_overlapping(entity.x, entity.y).each {|s| s << entity }
  end

  # Remove the entity from the grid
  def remove_entity_from_grid(entity)
    cells_overlapping(entity.x, entity.y).each do |s|
      raise "#{entity} not where expected" unless s.delete? entity
    end
  end

  # Update grid after an entity moves
  def update_grid_for_moved_entity(entity, old_x, old_y)
    cells_before = cells_overlapping(old_x, old_y)
    cells_after = cells_overlapping(entity.x, entity.y)

    (cells_before - cells_after).each do |s|
      raise "#{entity} not where expected" unless s.delete? entity
    end
    (cells_after - cells_before).each {|s| s << entity }
  end

  # Execute a block during which an entity may move
  # If it did, we will update the grid appropriately, and wake nearby entities
  #
  # All entity motion should be passed through this method
  def process_moving_entity(entity)
    unless @registry[entity.registry_id]
      puts "#{entity} not in registry yet, no move to process"
      yield
      return
    end

    before_x, before_y = entity.x, entity.y

    yield

    if moved = (entity.x != before_x || entity.y != before_y)
      update_grid_for_moved_entity(entity, before_x, before_y)
      # Note: Maybe we should only wake entities in either set
      # and not both.  For now we'll wake them all
      (
        entities_bordering_entity_at(before_x, before_y) +
        entities_bordering_entity_at(entity.x, entity.y)
      ).each(&:wake!)
    end

    moved
  end

  # List of entities by type matching the specified entity
  def entity_list(entity)
    case entity
    when Player then @players
    else @npcs
    end
  end

  # Override to be informed when trying to add an entity that
  # we already have (registry ID clash)
  def fire_duplicate_id(old_entity, new_entity); end

  # Add an entity.  Will wake neighboring entities
  def <<(entity)
    reg_id = entity.registry_id
    if old = self[reg_id]
      fire_duplicate_id(old, entity)
      old
    else
      @registry[reg_id] = entity
      entity_list(entity) << entity
      add_entity_to_grid(entity)
      entities_bordering_entity_at(entity.x, entity.y).each(&:wake!)
      entity
    end
  end

  # Doom an entity (mark it to be deleted but don't remove it yet)
  def doom(entity); @doomed << entity; end

  def doomed?(entity); @doomed.include?(entity); end

  # Override to be informed when trying to purge an entity that
  # turns out not to exist
  def fire_entity_not_found(entity); end

  # Actually remove all previously-marked entities.  Wakes neighbors
  def purge_doomed_entities
    @doomed.each do |entity|
      if @registry.delete entity.registry_id
        entities_bordering_entity_at(entity.x, entity.y).each(&:wake!)
        remove_entity_from_grid(entity)
        entity_list(entity).delete entity
      else
        fire_entity_not_found(entity)
      end
    end
    @doomed.clear
  end

  def update
    purge_doomed_entities

    @registry.values.find_all(&:moving?).each(&:update)

    check_for_grid_corruption
  end

  # Assertion
  def check_for_grid_corruption
    0.upto(@cell_height - 1) do |cell_y|
      0.upto(@cell_width - 1) do |cell_x|
        cell = at(cell_x, cell_y)
        cell.each do |entity|
          ok = cells_overlapping(entity.x, entity.y)
          unless ok.include? cell
            raise "#{entity} shouldn't be in cell #{cell}"
          end
        end
      end
    end
    @registry.values.each do |entity|
      cells_overlapping(entity.x, entity.y).each do |cell|
        unless cell.include? entity
          raise "Expected #{entity} to be in cell #{cell}"
        end
      end
    end
  end

  # Assertion.  Used server-side only
  def check_for_registry_leaks
    expected = @players.size + @npcs.size
    actual = @registry.size
    if expected != actual
      raise "We have #{expected} game entities, #{actual} in registry (delta: #{actual - expected})"
    end
  end

  # Used client-side only.  Determine an appropriate camera position,
  # given the specified window size, and preferring that the specified entity
  # be in the center.  Inputs and outputs are in pixels
  def good_camera_position_for(entity, screen_width, screen_height)
    # Given plenty of room, put the entity in the middle of the screen
    # If doing so would expose the area outside the world, move the camera just enough
    # to avoid that
    # If the world is smaller than the window, center it

#   puts "Screen in pixels is #{screen_width}x#{screen_height}; world in pixels is #{pixel_width}x#{pixel_height}"
    camera_x = if screen_width > pixel_width
      (pixel_width - screen_width) / 2 # negative
    else
      [[entity.pixel_x - screen_width/2, pixel_width - screen_width].min, 0].max
    end
    camera_y = if screen_height > pixel_height
      (pixel_height - screen_height) / 2 # negative
    else
      [[entity.pixel_y - screen_height/2, pixel_height - screen_height].min, 0].max
    end

#   puts "Camera at #{camera_x}x#{camera_y}"
    [ camera_x, camera_y ]
  end
end
