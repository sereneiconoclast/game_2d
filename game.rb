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

# By default, Gosu calls update() 60 times per second.
# We aim to match that.
TICKS_PER_SECOND = 60

# How many ticks between broadcasts of the registry
DEFAULT_REGISTRY_BROADCAST_EVERY = TICKS_PER_SECOND / 4

class Game
  def initialize(args)
    $server = true

    @storage = Storage.in_home_dir(args[:storage] || DEFAULT_STORAGE).dir('server')
    level_storage = @storage[args[:level]]

    if level_storage.empty?
      @space = GameSpace.new(self).establish_world(
        args[:width] || WORLD_WIDTH,
        args[:height] || WORLD_HEIGHT)
      @space.storage = level_storage
    else
      @space = GameSpace.load(self, level_storage)
    end

    @tick = 0
    @player_actions = Hash.new {|h,tick| h[tick] = Array.new}

    @self_check, @profile, @registry_broadcast_every = args.values_at(
    :self_check, :profile, :registry_broadcast_every)
    @registry_broadcast_every ||= DEFAULT_REGISTRY_BROADCAST_EVERY

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

    @port = _create_server_port(self,
      args[:port] || DEFAULT_PORT,
      args[:max_clients] || MAX_CLIENTS)
  end

  def _create_server_port(*args)
    ServerPort.new *args
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

  def process_player_actions
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
  end

  def update
    @port.update
    process_player_actions
    @space.update

    @port.broadcast(:registry => @space.registry.values, :at_tick => @tick) if
      @registry_broadcast_every > 0 && (@tick % @registry_broadcast_every == 0)

    if @self_check
      @space.check_for_grid_corruption
      @space.check_for_registry_leaks
    end
  end

  def run
    run_start = Time.now.to_r
    loop do
      TICKS_PER_SECOND.times do |n|
        update
        @tick += 1

        # This results in something approaching TICKS_PER_SECOND
        @port.update_until(run_start + Rational(@tick, TICKS_PER_SECOND))

        $stderr.puts "Updates per second: #{@tick / (Time.now.to_r - run_start)}" if @profile
      end # times
    end # infinite loop
  end # run

end

if $PROGRAM_NAME == __FILE__
  opts = Trollop::options do
    opt :level, "Level name", :type => :string, :required => true
    opt :width, "Level width", :type => :integer
    opt :height, "Level height", :type => :integer
    opt :port, "Port number", :type => :integer
    opt :storage, "Data storage dir (in home directory)", :type => :string
    opt :max_clients, "Maximum clients", :type => :integer
    opt :self_check, "Run data consistency checks", :type => :boolean
    opt :profile, "Turn on profiling", :type => :boolean
    opt :debug_traffic, "Debug network traffic", :type => :boolean
    opt :registry_broadcast_every, "Send registry broadcasts every N frames (0 = never)", :type => :integer
  end

  $debug_traffic = opts[:debug_traffic] || false

  Game.new(opts).run
end