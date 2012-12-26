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

class GameSpace
  attr_reader :registry, :players, :npcs, :width, :height

  def initialize
    @grid = nil

    @registry = {}

    # I create a @doomed array so we can remove entities after all collisions
    # have been processed, to avoid confusion
    @doomed = []

    @players = Array.new
    @npcs = Array.new
  end

  # Width and height, measured in cells
  # TODO: This may now be safe to fold into initialize()
  def establish_world(width, height)
    puts "World is #{width}x#{height} cells"
    @width, @height = width, height

    # Outer array is X-indexed; inner arrays are Y-indexed
    # Therefore you can look up @grid[x][y]
    # However, for convenience, we make the grid two cells wider, two cells
    # taller.
    # Then we can populate the edge with Wall instances, and treat (0, 0) as
    # a usable coordinate.  (-1, -1) contains a Wall
    # The at() and set_at() methods do the translation, so only they should
    # access @grid directly
    @grid = Array.new(width + 2) { Array.new(height + 2) }

    # Top and bottom, including corners
    (-1 .. width).each do |cell_x|
      set_at(cell_x, -1, Wall.new(self, cell_x, -1))         # top
      set_at(cell_x, height, Wall.new(self, cell_x, height)) # bottom
    end

    # Left and right, skipping corners
    (0 .. height - 1).each do |cell_y|
      set_at(-1, cell_y, Wall.new(self, -1, cell_y))       # left
      set_at(width, cell_y, Wall.new(self, width, cell_y)) # right
    end

    self
  end

  def pixel_width; @width * Entity::PIXEL_WIDTH; end
  def pixel_height; @height * Entity::PIXEL_WIDTH; end

  # Retrieve entity by ID
  def [](registry_id)
    @registry[registry_id]
  end

  # We can safely look up cell_x == -1, cell_x == @width, cell_y == -1, and/or
  # cell_y == @height -- this returns a Wall instance
  def assert_ok_coords(cell_x, cell_y)
    raise "Illegal coordinate #{cell_x}x#{cell_y}" if (
      cell_x < -1 ||
      cell_y < -1 ||
      cell_x > @width ||
      cell_y > @height
    )
  end

  # Retrieve single entity by cell coordinates, zero-based
  def at(cell_x, cell_y)
    assert_ok_coords(cell_x, cell_y)
    @grid[cell_x - 1][cell_y - 1]
  end

  # Low-level setter
  def set_at(cell_x, cell_y, entity)
    assert_ok_coords(cell_x, cell_y)
    @grid[cell_x - 1][cell_y - 1] = entity
  end

  # Retrieve set of entities by list of coordinates ([cell_x, cell_y] tuples)
  # This returns a set
  def contents(coords)
    coords.collect {|cell_x, cell_y| at(cell_x, cell_y) }.compact.to_set
  end

  # Retrieve set of entities that overlap with a theoretical entity created at
  # position [x, y] (in subpixels)
  def contents_overlapping(x, y)
    contents([
      [Entity.left_cell_x_at(x), Entity.top_cell_y_at(y)],
      [Entity.right_cell_x_at(x), Entity.top_cell_y_at(y)],
      [Entity.left_cell_x_at(x), Entity.bottom_cell_y_at(y)],
      [Entity.right_cell_x_at(x), Entity.bottom_cell_y_at(y)],
    ])
  end

  # Update grid after an entity moves
  # cells_before and cells_after are both lists of coords ([cell_x, cell_y]
  # tuples)
  # all of cells_before must currently contain 'entity'
  # all of cells_after must currently be empty
  def update_grid(entity, cells_before, cells_after)
    (cells_before - cells_after).each do |cell_x, cell_y|
      before = at(cell_x, cell_y)
      raise "Cell #{cell_x}x#{cell_y} contains #{before}, not #{entity}" unless before == entity
      set_at(cell_x, cell_y, nil)
    end
    (cells_after - cells_before).each do |cell_x, cell_y|
      before = at(cell_x, cell_y)
      raise "Cell #{cell_x}x#{cell_y} contains #{before}, not empty" if before
      set_at(cell_x, cell_y, entity)
    end
  end

  # Execute a block during which an entity may move
  # If it did, we will update the grid appropriately, and wake nearby entities
  #
  # All entity motion should be passed through this method
  def process_moving_entity(entity)
    before_x, before_y = entity.x, entity.y
    before_cells = entity.occupied_cells
    nearby_x_before = entity.nearby_x_range
    nearby_y_before = entity.nearby_y_range

    yield

    if moved = (entity.x != before_x || entity.y != before_y)
      update_grid(entity, before_cells, entity.occupied_cells)
      # TODO - this only works if the entity slides from one cell into an
      # adjoining one.  If it actually teleports, it wakes far more cells than
      # necessary...
      wake_area(
        nearby_x_before + entity.nearby_x_range,
        nearby_y_before + entity.nearby_y_range
      )
    end

    moved
  end

  # List of entities by type matching the specified entity
  def entity_list(entity)
    case entity
    when Player then @players
    when NPC then @npcs
    else raise "Unknown entity type: #{entity} (#{entity.class})"
    end
  end

  # Override to be informed when trying to add an entity that
  # we already have (registry ID clash)
  def fire_duplicate_id(old_entity, new_entity); end

  # Add an entity
  def <<(entity)
    reg_id = entity.registry_id
    if old = self[reg_id]
      fire_duplicate_id(old, entity)
      old
    else
      @registry[reg_id] = entity
      entity_list(entity) << entity
      update_grid(entity, [], entity.occupied_cells)
      entity
    end
  end

  # Doom an entity (mark it to be deleted but don't remove it yet)
  def doom(entity); @doomed << entity; end

  def doomed?(entity); @doomed.include?(entity); end

  # Override to be informed when trying to purge an entity that
  # turns out not to exist
  def fire_entity_not_found(entity); end

  def purge_doomed_entities
    @doomed.each do |entity|
      if @registry.delete entity.registry_id
        entity.wake_surroundings
        update_grid(entity, entity.occupied_cells, [])
        entity_list(entity).delete entity
      else
        fire_entity_not_found(entity)
      end
    end
    @doomed.clear
  end

  def wake_area(x_range, y_range)
    x_range.each do |cell_x|
      y_range.each do |cell_y|
        at(cell_x, cell_y).wake!
      end
    end
  end

  def dequeue_player_moves
    @players.each &:dequeue_move
  end

  def update
    purge_doomed_entities

    # Process commands by all players
    @players.each &:execute_move

    @registry.values.find_all(&:moving?).each(&:update)
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
  # be in the center
  def good_camera_position_for(entity, screen_width, screen_height)
    # Given plenty of room, put the entity in the middle of the screen
    # If doing so would expose the area outside the world, move the camera just enough
    # to avoid that
    # If the world is smaller than the window, center it

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

    [ camera_x, camera_y ]
  end
end
