## Author: Greg Meyers
## License: Same as for Gosu (MIT)

require 'rubygems'
require 'trollop'
require 'gosu'

$LOAD_PATH << '.'
require 'storage'
require 'server_port'
require 'game_space'
require 'player'
require 'npc'

WORLD_WIDTH = 100 # in cells
WORLD_HEIGHT = 70 # in cells

DEFAULT_PORT = 4321
DEFAULT_STORAGE = '.cnstruxn'
MAX_CLIENTS = 32

# How many cycles between broadcasts of the registry
REGISTRY_BROADCAST_EVERY=60 / 4 # Four times a second

class Game
  def initialize(storage, level, cell_width, cell_height)
    @storage = Storage.in_home_dir(storage).dir('server')
    level_storage = @storage[level]

    if level_storage.empty?
      @space = GameSpace.new.establish_world(cell_width, cell_height)
      @space.storage = level_storage
    else
      @space = GameSpace.load(level_storage)
    end

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

  def delete_player(player)
    puts "Deleting #{player}"
    @space.doom player
    @space.purge_doomed_entities
    @space.players.each {|other| other.conn.delete_player player }
  end

  def create_npc(npc)
    x, y = npc['x'], npc['y']
    conflicts = @space.entities_overlapping(x, y)
    if conflicts.empty?
      npc = NPC.new(@space, x, y)
      npc.generate_id
#     npc.a = rand(360)
      puts "Created #{npc}"
      @space << npc
      @space.players.each {|p| p.conn.add_npc npc }
    else
      # TODO: Convey error to user somehow
      puts "Can't create NPC at #{x}x#{y}, occupied by #{conflicts.inspect}"
    end
  end

  def get_all_players
    @space.players
  end

  def get_all_npcs
    @space.npcs
  end

  def run(server_port)
    loop do

      cycle_start = Time.now.to_r
      60.times do |n|
        @space.dequeue_player_moves

        @space.update
        server_port.update

        @space.check_for_registry_leaks

        server_port.broadcast(:registry => @space.registry) if (n % REGISTRY_BROADCAST_EVERY == 0)

        # This results in almost exactly 60 updates per second
        desired_time = cycle_start + Rational((n + 1), 60)
        while Time.now.to_r < desired_time do
          server_port.update
        end
      end # 60.times

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
end

game = Game.new(opts[:storage], opts[:level], opts[:width], opts[:height])

server_port = ServerPort.new(game, opts[:port], opts[:max_clients])

puts "ENet server listening on #{opts[:port]}"
game.run(server_port)
