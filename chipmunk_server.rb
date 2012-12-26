## File: ChipmunkIntegration.rb
## Author: Dirk Johnson
## Version: 1.0.0
## Date: 2007-10-05
## License: Same as for Gosu (MIT)
## Comments: Based on the Gosu Ruby Tutorial, but incorporating the Chipmunk Physics Engine
## See https://github.com/jlnr/gosu/wiki/Ruby-Chipmunk-Integration for the accompanying text.

require 'rubygems'
require 'gosu'

$LOAD_PATH << '.'
require 'server_port'
require 'game_space'
require 'player'
require 'npc'

WORLD_WIDTH = 100 # in cells
WORLD_HEIGHT = 70 # in cells

PORT = 4321
MAX_CLIENTS = 32

# How many cycles between broadcasts of the registry
REGISTRY_BROADCAST_EVERY=60 / 4 # Four times a second

class Game
  def initialize
    @space = GameSpace.new.establish_world(world_width, world_height)

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

  def world_width; WORLD_WIDTH; end
  def world_height; WORLD_HEIGHT; end

  def add_player(conn, player_name)
    player = Player.new(@space, conn, player_name)
    player.generate_id
    player.warp(world_width / 2, world_height / 2) # coords in cells
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
    conflicts = @space.contents_overlapping(x, y)
    if conflicts.empty?
      npc = NPC.new(@space, x, y)
      npc.generate_id
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

game = Game.new

server_port = ServerPort.new(game, PORT, MAX_CLIENTS)

puts "ENet server listening on #{PORT}"
game.run(server_port)
