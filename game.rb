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
  def initialize(
    port_number, max_clients, storage,
    level, cell_width, cell_height,
    self_check, profile
  )
    $server = true

    @storage = Storage.in_home_dir(storage).dir('server')
    level_storage = @storage[level]

    if level_storage.empty?
      @space = GameSpace.new(self).establish_world(cell_width, cell_height)
      @space.storage = level_storage
    else
      @space = GameSpace.load(self, level_storage)
    end

    @tick = 0
    @player_actions = Hash.new {|h,tick| h[tick] = Array.new}

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

    @port = ServerPort.new(self, port_number, max_clients)
  end

  attr_reader :tick

  def world_cell_width; @space.cell_width; end
  def world_cell_height; @space.cell_height; end

  def save
    @space.save
  end

  def add_player(player_name)
    player = Player.new(player_name)
    player.generate_id
    player.x = (@space.width - Entity::WIDTH) / 2
    player.y = (@space.height - Entity::HEIGHT) / 2
    # We notify existing players first, *then* add the new player
    @space.players.each {|p| player_connection(p).add_player(player, @tick) }
    @space << player
  end

  def player_id_connection(player_id)
    @port.player_connection(player_id)
  end

  def player_connection(player)
    player_id_connection(player.registry_id)
  end

  def delete_entity(entity)
    puts "Deleting #{entity}"
    @space.doom entity
    @space.purge_doomed_entities
    @space.players.each {|player| player_connection(player).delete_entity entity, @tick }
  end

  # Answering request from client
  def create_npc(json)
    add_npc(Entity.from_json(json, :GENERATE_ID))
  end

  def add_npc(npc)
    @space << npc or return
    puts "Created #{npc}"
    @space.players.each {|p| player_connection(p).add_npc npc, @tick }
  end

  def send_updated_entity(entity)
    @space.players.each {|p| player_connection(p).update_entity entity, @tick }
  end

  def [](id)
    @space[id]
  end

  def get_all_players
    @space.players
  end

  def get_all_npcs
    @space.npcs
  end

  def add_player_action(player_id, action)
    at_tick = action['at_tick']
    unless at_tick
      $stderr.puts "Received update from #{player_id} without at_tick!"
      at_tick = @tick + 1
    end
    if at_tick <= @tick
      $stderr.puts "Received update from #{player_id} #{@tick + 1 - at_tick} ticks late"
      at_tick = @tick + 1
    end
    @player_actions[at_tick] << [player_id, action]
  end

  def run
    # We'll update this every second.  Needs to exist before we create the proc
    cycle_start = Time.now.to_r

    main_block = proc do |n|
      if actions = @player_actions.delete(@tick)
        actions.each do |player_id, action|
          player = @space[player_id]
          unless player
            $stderr.puts "No such player #{player_id} -- dropping move"
            next
          end
          if (move = action['move'])
            player.add_move move
          elsif (npc = action['create_npc'])
            create_npc npc
          else
            $stderr.puts "IGNORING BAD DATA from #{player}: #{action.inspect}"
          end
        end
      end

      @space.update
      @port.update

      @port.broadcast(:registry => @space.registry, :at_tick => @tick) if
        (@tick % REGISTRY_BROADCAST_EVERY == 0)

      if @self_check
        @space.check_for_grid_corruption
        @space.check_for_registry_leaks
      end

      @tick += 1

      unless @profile
        # This results in almost exactly 60 updates per second
        @port.update_until(cycle_start + Rational((n + 1), 60))
      end
    end # main_block

    loop do
      cycle_start = Time.now.to_r
      if @profile
        avg = 60.times_profiled(&main_block)
        puts "Average time for run(): #{avg}"
        @port.update_until(cycle_start + 1)
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
  opts[:port], opts[:max_clients],
  opts[:storage], opts[:level], opts[:width], opts[:height],
  opts[:self_check], opts[:profile])

game.run