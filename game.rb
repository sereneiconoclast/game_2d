## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'trollop'
require 'gosu'

$LOAD_PATH << '.'
require 'storage'
require 'server_port'
require 'game_space'
require 'entity'
require 'player'

WORLD_WIDTH = 100 # in cells
WORLD_HEIGHT = 70 # in cells

DEFAULT_PORT = 4321
DEFAULT_STORAGE = '.cnstruxn'
MAX_CLIENTS = 32

# How many cycles between broadcasts of the registry
REGISTRY_BROADCAST_EVERY=60 / 4 # Four times a second

class Fixnum
  def times_profiled
    sum = 0.0
    times do |n|
      before = Time.now.to_f
      yield n
      after = Time.now.to_f
      sum += (after - before)
    end
    sum / self
  end
end

class Game
  def initialize(storage, level, cell_width, cell_height, self_check, profile)
    @storage = Storage.in_home_dir(storage).dir('server')
    level_storage = @storage[level]

    if level_storage.empty?
      @space = GameSpace.new(self).establish_world(cell_width, cell_height)
      @space.storage = level_storage
    else
      @space = GameSpace.load(self, level_storage)
    end

    @self_check, @profile = self_check, profile

    # This should never happen.  It can only happen client-side because a
    # registry update may create an entity before we get around to it in,
    # say, add_npc
    def @space.fire_duplicate_id(old_entity, new_entity)
      raise "#{old_entity} and #{new_entity} have same ID!"
    end

    # This should never happen.  It can only happen client-side because a
    # registry update may delete an entity before we get around to it in
    # purge_doomed_entities
    def @space.fire_entity_not_found(entity)
      raise "Object #{entity} not in registry"
    end
  end

  def world_cell_width; @space.cell_width; end
  def world_cell_height; @space.cell_height; end

  def save
    @space.save
  end

  def add_player(conn, player_name)
    player = Player.new(@space, conn, player_name)
    player.generate_id
    player.x, player.y = @space.width / 2, @space.height / 2
    @space.players.each {|p| p.conn.add_player(player) }
    @space << player
  end

  def delete_entity(entity)
    puts "Deleting #{entity}"
    @space.doom entity
    @space.purge_doomed_entities
    @space.players.each {|player| player.conn.delete_entity entity }
  end

  def create_npc(json)
    add_npc(Entity.from_json(@space, json, :GENERATE_ID))
  end

  def add_npc(npc)
    conflicts = npc.entities_obstructing(npc.x, npc.y)
    if conflicts.empty?
      puts "Created #{npc}"
      @space << npc
      @space.players.each {|p| p.conn.add_npc npc }
    else
      # TODO: Convey error to user somehow
      puts "Can't create #{npc}, occupied by #{conflicts.inspect}"
    end
  end

  def get_all_players
    @space.players
  end

  def get_all_npcs
    @space.npcs
  end

  def run(server_port)
    # We'll update this every second.  Needs to exist before we create the proc
    cycle_start = Time.now.to_r

    main_block = proc do |n|
      @space.update
      server_port.update

      server_port.broadcast(:registry => @space.registry) if (n % REGISTRY_BROADCAST_EVERY == 0)

      if @self_check
        @space.check_for_grid_corruption
        @space.check_for_registry_leaks
      end

      unless @profile
        # This results in almost exactly 60 updates per second
        server_port.update_until(cycle_start + Rational((n + 1), 60))
      end
    end # main_block

    loop do
      cycle_start = Time.now.to_r
      if @profile
        avg = 60.times_profiled(&main_block)
        puts "Average time for run(): #{avg}"
        server_port.update_until(cycle_start + 1)
      else
        60.times(&main_block)
      end
    end # infinite loop
  end

end

opts = Trollop::options do
  opt :level, "Level name", :type => :string, :required => true
  opt :width, "Level width", :default => WORLD_WIDTH
  opt :height, "Level height", :default => WORLD_HEIGHT
  opt :port, "Port number", :default => DEFAULT_PORT
  opt :storage, "Data storage dir (in home directory)", :default => DEFAULT_STORAGE
  opt :max_clients, "Maximum clients", :default => MAX_CLIENTS
  opt :self_check, "Run data consistency checks", :type => :boolean
  opt :profile, "Turn on profiling", :type => :boolean
end

game = Game.new(
  opts[:storage], opts[:level], opts[:width], opts[:height],
  opts[:self_check], opts[:profile])

server_port = ServerPort.new(game, opts[:port], opts[:max_clients])

puts "ENet server listening on #{opts[:port]}"
game.run(server_port)
