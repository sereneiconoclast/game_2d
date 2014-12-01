require 'securerandom'
require 'delegate'
require 'set'
require 'facets/kernel/try'
require 'game_2d/wall'
require 'game_2d/player'
require 'game_2d/serializable'
require 'game_2d/entity_constants'
require 'game_2d/entity/owned_entity'

# Common code between the server and client for maintaining the world.
# This is a bounded space (walls on all sides).
#
# Maintains a registry of entities.  All game entities must have a registry_id
# set before they will be accepted.
#
# Also maintains a list of entities due to be deleted, to avoid removing them
# at the wrong time (during collision processing).

# Cell is a portion of the game space, the exact size of one entity.
# The cell (0,0) contains subpixel coordinates (0,0) through (399,399).
#
# The behavior I want from Cells is to consider them all unique objects.
# I want to be able to say "Subtract this set of cells from that set".  Treating
# Cells as equal if their contents are equal defeats this purpose.
#
# It's also handy if each Cell knows where it lives in the grid.
#
# Previously, I was using Set as the superclass.  That seemed to make sense,
# since this is an unordered collection.  But Set stores everything as hash
# keys, and hashes get very confused if their keys get mutated without going
# through the API.

class Cell < DelegateClass(Array)
  attr_reader :x, :y

  def ==(other)
    other.class.equal?(self.class) &&
      other.x == self.x &&
      other.y == self.y &&
      other.instance_variable_get(:@a) == @a
  end

  def initialize(cell_x, cell_y)
    @a = []
    @x, @y = cell_x, cell_y
    super(@a)
  end

  def to_s; "(#{x}, #{y}) [#{@a.join(', ')}]"; end
  def inspect; "Cell(#{x}, #{y}) #{@a}"; end
end


class GameSpace
  include EntityConstants

  attr_reader :world_name, :world_id, :players, :npcs, :cell_width, :cell_height, :game
  attr_accessor :storage, :highest_id

  def initialize(game=nil)
    @game = game
    @grid = @storage = nil
    @highest_id = 0

    @registry = {}

    # Ownership registry needs to be here too.  Each copy of the space must be
    # separate.  Otherwise you get duplicate entries whenever ClientEngine copies
    # the GameSpace.
    #
    # owner.registry_id => [registry_id, ...]
    @ownership = Hash.new {|h,k| h[k] = Array.new}

    # I create a @doomed array so we can remove entities after all collisions
    # have been processed, to avoid confusion
    @doomed = []

    @players = []
    @npcs = []
  end

  # Width and height, measured in cells
  def establish_world(name, id, cell_width, cell_height)
    @world_name = name
    @world_id = (id || SecureRandom.uuid).to_sym
    @cell_width, @cell_height = cell_width, cell_height

    # Outer array is X-indexed; inner arrays are Y-indexed
    # Therefore you can look up @grid[cell_x][cell_y] ...
    # However, for convenience, we make the grid two cells wider, two cells
    # taller.  Then we can populate the edge with Wall instances, and treat (0,
    # 0) as a usable coordinate.  (-1, -1) contains a Wall, for example.  The
    # at(), put(), and cut() methods do the translation, so only they should
    # access @grid directly
    @grid = Array.new(cell_width + 2) do |cx|
      Array.new(cell_height + 2) do |cy|
        Cell.new(cx-1, cy-1)
      end.freeze
    end.freeze

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

  def copy_from(original)
    establish_world(original.world_name, original.world_id, original.cell_width, original.cell_height)
    @highest_id = original.highest_id

    # @game and @storage should point to the same object (no clone)
    @game, @storage = original.game, original.storage

    # Registry should contain all objects - clone those
    original.all_registered.each {|ent| self << ent.clone }

    self
  end

  def self.load(game, storage)
    name, id, cell_width, cell_height =
      storage[:world_name], storage[:world_id],
      storage[:cell_width], storage[:cell_height]
    space = GameSpace.new(game).establish_world(name, id, cell_width, cell_height)
    space.storage = storage
    space.load
  end

  def save
    @storage[:world_name] = @world_name
    @storage[:world_id] = @world_id
    @storage[:cell_width], @storage[:cell_height] = @cell_width, @cell_height
    @storage[:highest_id] = @highest_id
    @storage[:npcs] = @npcs
    @storage.save
  end

  # TODO: Handle this while server is running and players are connected
  # TODO: Handle resizing the space
  def load
    @highest_id = @storage[:highest_id]
    @storage[:npcs].each do |json|
      puts "Loading #{json.inspect}"
      self << Serializable.from_json(json)
    end
    self
  end

  def pixel_width; @cell_width * CELL_WIDTH_IN_PIXELS; end
  def pixel_height; @cell_height * CELL_WIDTH_IN_PIXELS; end
  def width; @cell_width * WIDTH; end
  def height; @cell_height * HEIGHT; end

  def next_id
    "R#{@highest_id += 1}".to_sym
  end

  # Retrieve entity by ID
  def [](registry_id)
    return nil unless registry_id
    @registry[registry_id.to_sym]
  end

  def all_registered
    @registry.values
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

  # Returns nil if registration worked, or the exact same object
  # was already registered
  # If another object was registered, calls fire_duplicate_id and
  # then returns the previously-registered object
  def register(entity)
    reg_id = entity.registry_id
    old = @registry[reg_id]
    return nil if old.equal? entity
    if old
      fire_duplicate_id(old, entity)
      return old
    end
    @registry[reg_id] = entity
    entity_list(entity) << entity
    register_with_owner(entity)
    nil
  end

  def registered?(entity)
    return false unless old = @registry[entity.registry_id]
    return true if old.equal? entity
    fail("Registered entity #{old} has ID #{old.object_id}; " +
      "passed entity #{entity} has ID #{entity.object_id}")
  end

  def deregister(entity)
    fail "#{entity} not registered" unless registered?(entity)
    deregister_ownership(entity)
    entity_list(entity).delete entity
    @registry.delete entity.registry_id
  end

  def register_with_owner(owned)
    return unless owned.is_a?(Entity::OwnedEntity) && owned.owner_id
    @ownership[owned.owner_id] << owned.registry_id
  end

  def deregister_ownership(entity)
    if entity.is_a?(Entity::OwnedEntity) && entity.owner_id
      @ownership[entity.owner_id].delete entity.registry_id
    end
    @ownership.delete entity.registry_id
  end

  def owner_change(owned_id, old_owner_id, new_owner_id)
    return unless owned_id
    return if old_owner_id == new_owner_id
    @ownership[old_owner_id].delete(owned_id) if old_owner_id
    @ownership[new_owner_id] << owned_id if new_owner_id
  end

  def possessions(entity)
    @ownership[entity.registry_id].collect {|id| self[id]}
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
    @grid[cell_x + 1][cell_y + 1]
  end

  # Low-level adder
  def put(cell_x, cell_y, entity)
    at(cell_x, cell_y) << entity
  end

  # Low-level remover
  def cut(cell_x, cell_y, entity)
    at(cell_x, cell_y).delete entity
  end

  # Translate a subpixel point (X, Y) to a cell coordinate (cell_x, cell_y)
  def cell_location_at_point(x, y)
    [x / WIDTH, y / HEIGHT ]
  end

  # Translate multiple subpixel points (X, Y) to a set of cell coordinates
  # (cell_x, cell_y)
  def cell_locations_at_points(coords)
    coords.collect {|x, y| cell_location_at_point(x, y) }.to_set
  end

  # Given the (X, Y) position of a theoretical entity, return the list of all
  # the coordinates of its corners
  def corner_points_of_entity(x, y)
    [
      [x, y],
      [x + WIDTH - 1, y],
      [x, y + HEIGHT - 1],
      [x + WIDTH - 1, y + HEIGHT - 1],
    ]
  end

  # Return a list of the entities (if any) at a subpixel point (X, Y)
  def entities_at_point(x, y)
    at(*cell_location_at_point(x, y)).find_all do |e|
      e.x <= x && e.x > (x - WIDTH) &&
      e.y <= y && e.y > (y - HEIGHT)
    end
  end

  # Return whichever entity's center is closest (or ties for closest)
  def near_to(x, y)
    entities_at_point(x, y).collect do |entity|
      center_x = entity.x + WIDTH/2
      center_y = entity.y + HEIGHT/2
      delta_x = (center_x - x).abs
      delta_y = (center_y - y).abs
      distance = Math.sqrt(delta_x**2 + delta_y**2)
      [distance, entity]
    end.sort {|(d1, e1), (d2, e2)| d1 <=> d2}.first.try(:last)
  end

  # Accepts a collection of (x, y)
  # Returns a Set of entities
  def entities_at_points(coords)
    coords.collect {|x, y| entities_at_point(x, y) }.flatten.to_set
  end

  # The set of entities that may be affected by an entity moving to (or from)
  # the specified (x, y) coordinates
  # This includes the coordinates of eight points just beyond the entity's
  # borders
  def entities_bordering_entity_at(x, y)
    r = x + WIDTH - 1
    b = y + HEIGHT - 1
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

  # Retrieve list of cell-coordinates (expressed as [cell_x, cell_y]
  # arrays), coinciding with position [x, y] (expressed in subpixels).
  def cell_locations_overlapping(x, y)
    cell_locations_at_points(corner_points_of_entity(x, y))
  end

  # Retrieve list of cells that overlap with a theoretical entity
  # at position [x, y] (in subpixels).
  def cells_overlapping(x, y)
    cell_locations_overlapping(x, y).collect {|cx, cy| at(cx, cy) }
  end

  # Add the entity to the grid
  def add_entity_to_grid(entity)
    cells_overlapping(entity.x, entity.y).each {|s| s << entity }
  end

  # Remove the entity from the grid
  def remove_entity_from_grid(entity)
    cells_overlapping(entity.x, entity.y).each do |s|
      raise "#{entity} not where expected" unless s.delete entity
    end
  end

  # Update grid after an entity moves
  def update_grid_for_moved_entity(entity, old_x, old_y)
    cells_before = cells_overlapping(old_x, old_y)
    cells_after = cells_overlapping(entity.x, entity.y)

    (cells_before - cells_after).each do |s|
      raise "#{entity} not where expected" unless s.delete entity
    end
    (cells_after - cells_before).each {|s| s << entity }
  end

  # Execute a block during which an entity may move
  # If it did, we will update the grid appropriately, and wake nearby entities
  #
  # All entity motion should be passed through this method
  def process_moving_entity(entity)
    unless registered?(entity)
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

  # Add an entity.  Will wake neighboring entities
  def <<(entity)
    entity.registry_id = next_id unless entity.registry_id?

    fail "Already registered: #{entity}" if registered?(entity)

    # Need to assign the space before entities_obstructing()
    entity.space = self
    conflicts = entity.entities_obstructing(entity.x, entity.y)
    if conflicts.empty?
      register(entity)
      add_entity_to_grid(entity)
      entities_bordering_entity_at(entity.x, entity.y).each(&:wake!)
      entity
    else
      entity.space = nil
      # TODO: Convey error to user somehow
      $stderr.puts "Can't create #{entity}, occupied by #{conflicts.inspect}"
    end
  end

  def snap_to_grid(entity_id)
    unless entity = self[entity_id]
      $stderr.puts "Can't snap #{entity_id}, doesn't exist"
      return
    end

    candidates = cell_locations_overlapping(entity.x, entity.y).collect do |cell_x, cell_y|
      [cell_x * WIDTH, cell_y * HEIGHT]
    end
    sorted = candidates.to_a.sort do |(ax, ay), (bx, by)|
      ((entity.x - ax).abs + (entity.y - ay).abs) <=>
      ((entity.x - bx).abs + (entity.y - by).abs)
    end
    sorted.each do |dx, dy|
      if entity.entities_obstructing(dx, dy).empty?
        entity.warp(dx, dy)
        entity.wake!
        return
      end
    end
    $stderr.puts "Couldn't snap #{entity} to grid"
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
      if registered?(entity)
        entity.destroy!
        deregister(entity)
        entities_bordering_entity_at(entity.x, entity.y).each(&:wake!)
        remove_entity_from_grid(entity)
      else
        fire_entity_not_found(entity)
      end
    end
    @doomed.clear
  end

  def update
    @registry.values.each do |ent|
      if ent.grabbed?
        ent.move
        ent.release!
        ent.x_vel = ent.y_vel = 0
      elsif ent.moving?
        ent.update
      end
    end
    purge_doomed_entities
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

  # Assertion.  Useful server-side only
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

  def ==(other)
    other.class.equal?(self.class) && other.all_state == self.all_state
  end
  def all_state
    [@world_name, @world_id, @registry, @grid, @highest_id]
  end
end
