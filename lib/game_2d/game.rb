## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'gosu'

require 'game_2d/storage'
require 'game_2d/server_port'
require 'game_2d/game_space'
require 'game_2d/serializable'
require 'game_2d/entity'
require 'game_2d/entity/gecko'
require 'game_2d/entity/ghost'

WORLD_WIDTH = 100 # in cells
WORLD_HEIGHT = 70 # in cells

DEFAULT_PORT = 4321
DEFAULT_STORAGE = '.game_2d'
MAX_CLIENTS = 32

# By default, Gosu calls update() 60 times per second.
# We aim to match that.
TICKS_PER_SECOND = 60

# How many ticks between broadcasts of the registry
DEFAULT_REGISTRY_BROADCAST_EVERY = TICKS_PER_SECOND / 4

class Game
  def initialize(args)
    all_storage = Storage.in_home_dir(args[:storage] || DEFAULT_STORAGE)
    @player_storage = all_storage.dir('players')['players']
    @levels_storage = all_storage.dir('levels')
    level_storage = @levels_storage[args[:level]]

    if level_storage.empty?
      @space = GameSpace.new(self).establish_world(
        args[:level],
        nil, # level ID
        args[:width] || WORLD_WIDTH,
        args[:height] || WORLD_HEIGHT)

      @space << Entity::Base.new(*@space.center)

      @space.storage = level_storage
    else
      @space = GameSpace.load(self, level_storage)
    end

    @tick = -1
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

  def world_name; @space.world_name; end
  def world_id; @space.world_id; end
  def world_highest_id; @space.highest_id; end
  def world_cell_width; @space.cell_width; end
  def world_cell_height; @space.cell_height; end

  def save
    @space.save
  end

  def player_data(player_name)
    @player_storage[player_name]
  end

  def store_player_data(player_name, data)
    @player_storage[player_name] = data
    @player_storage.save
  end

  def add_player(player_name)
    if base = @space.available_base
      player = Entity::Gecko.new(player_name)
      player.x, player.y, player.a = base.x, base.y, base.a
    else
      player = Entity::Ghost.new(player_name)
      player.x, player.y = @space.center
    end
    @space << player

    each_player_conn do |c|
      c.add_player(player, @tick) unless c.player_name == player_name
    end
    player
  end

  def replace_player_entity(player_name, new_player_id)
    conn = player_name_connection(player_name)
    old = conn.player_id
    conn.player_id = new_player_id
  end

  def player_name_connection(player_name)
    @port.player_name_connection(player_name)
  end

  def player_connection(player)
    player_name_connection(player.player_name)
  end

  def each_player_conn
    get_all_players.each {|p| pc = player_connection(p) and yield pc}
  end

  def send_player_gone(toast)
    @space.doom toast
    each_player_conn {|pc| pc.delete_entity toast, @tick }
  end

  def delete_entities(entities)
    entities.each do |registry_id|
      @space.doom(@space[registry_id])
    end
    @space.purge_doomed_entities
  end

  # Answering request from client
  def add_npcs(npcs_json)
    npcs_json.each {|json| @space << Serializable.from_json(json) }
  end

  def update_npcs(npcs_json)
    npcs_json.each do |json|
      id = json[:registry_id]
      if entity = @space[id]
        entity.update_from_json json
        entity.grab!
      else
        warn "Can't update #{id}, doesn't exist"
      end
    end
  end

  def send_updated_entities(*entities)
    each_player_conn {|pc| pc.update_entities entities, @tick }
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

  def add_player_action(action)
    at_tick, player_name = action[:at_tick], action[:player_name]
    unless at_tick
      at_tick = @tick + 1
      warn "Received update from #{player_name} without at_tick! - executing at #{at_tick}"
    end
    if at_tick <= @tick
      warn "Received update from #{player_name} #{@tick + 1 - at_tick} ticks late - executing at #{@tick + 1}"
      at_tick = @tick + 1
    end
    @player_actions[at_tick] << action
  end

  def process_player_actions
    if actions = @player_actions.delete(@tick)
      actions.each do |action|
        player_name = action.delete :player_name
        conn = player_name_connection(player_name)
        unless conn
          warn "No connection -- dropping move from #{player_name}"
          next
        end
        player_id = conn.player_id
        player = @space[player_id]
        unless player
          warn "No such player #{player_id} -- dropping move from #{player_name}"
          next
        end
        if (move = action[:move])
          player.add_move move
        elsif (npcs = action[:add_npcs])
          add_npcs npcs
        elsif (entities = action[:update_entities])
          update_npcs entities
        elsif (entities = action[:delete_entities])
          delete_entities entities
        elsif (entity_id = action[:snap_to_grid])
          @space.snap_to_grid entity_id.to_sym
        else
          warn "IGNORING BAD DATA from #{player_name}: #{action.inspect}"
        end
      end
    end
  end

  def update
    @tick += 1

    # This will:
    # 1) Queue up player actions for existing players
    #    (create_npc included)
    # 2) Add new players in response to login messages
    # 3) Remove players in response to disconnections
    @port.update

    # This will execute player moves, and create NPCs
    process_player_actions

    # Objects that exist by now will be updated
    # Objects created during this update won't be updated
    # themselves this tick
    @space.update

    # Do this at the end, so the update contains all the
    # latest and greatest news
    send_full_updates

    if @self_check
      @space.check_for_grid_corruption
      @space.check_for_registry_leaks
    end
  end

  # New players always get a full update (with some additional
  # information)
  # Everyone else gets full registry dump every N ticks, where
  # N == @registry_broadcast_every
  def send_full_updates
    # Set containing brand-new players' IDs
    # This is cleared after we read it
    new_players = @port.new_players

    each_player_conn do |pc|
      if new_players.include? pc.player_name
        response = {
          :you_are => pc.player_id,
          :world => {
            :world_name => world_name,
            :world_id => world_id,
            :highest_id => world_highest_id,
            :cell_width => world_cell_width,
            :cell_height => world_cell_height,
          },
          :add_players => get_all_players,
          :add_npcs => get_all_npcs,
          :at_tick => tick,
        }
        pc.send_record response, true # answer login reliably
      elsif @registry_broadcast_every > 0 && (@tick % @registry_broadcast_every == 0)
        pc.send_record( {
          :registry => @space.all_registered,
          :highest_id => @space.highest_id,
          :at_tick => @tick,
        }, false, 1 )
      end
    end
  end

  def run
    run_start = Time.now.to_r
    loop do
      TICKS_PER_SECOND.times do |n|
        update

        # This results in something approaching TICKS_PER_SECOND
        @port.update_until(run_start + Rational(@tick, TICKS_PER_SECOND))

        warn "Updates per second: #{@tick / (Time.now.to_r - run_start)}" if @profile
      end # times
    end # infinite loop
  end # run

end
