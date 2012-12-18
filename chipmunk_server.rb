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
require 'chipmunk_utilities'
require 'server_port'
require 'game_space'
require 'player'
require 'npc'

WORLD_WIDTH = 640
WORLD_HEIGHT = 480

PORT = 4321
MAX_CLIENTS = 32

# Tell physics engine to expect 60 updates per second
DELTA_T = 1.0/60.0

# The number of steps to process every Gosu update
$SUBSTEPS = 6

# How many cycles between broadcasts of the registry
REGISTRY_BROADCAST_EVERY=60 / 4 # Four times a second

class Game
  def initialize
    # Time increment over which to apply a physics "step"
    @space = GameSpace.new(DELTA_T)

    # This should never happen.  It can only happen client-side because a
    # registry update may create an object before we get around to it in,
    # say, add_npc
    def @space.fire_duplicate_id(old_object, new_object)
      raise "#{old_object} and #{new_object} have same ID!"
    end

    # This should never happen.  It can only happen client-side because a
    # registry update may delete an object before we get around to it in
    # purge_doomed_objects
    def @space.fire_object_not_found(object)
      raise "Object #{object} not in registry"
    end

    @space.establish_world(world_width, world_height)

    # Here we define what is supposed to happen when a Player (ship) collides with an NPC
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @space.add_collision_func(:ship, :npc) do |ship_shape, npc_shape|
      npc = npc_shape.body.object
      unless @space.doomed? npc # filter out duplicate collisions
        player = ship_shape.body.object
        player.score += 10
        @space.players.each {|p| p.conn.update_score player }
        @space.doom npc
        # remember to return 'true' if we want regular collision handling
      end
    end
  end

  def world_width; WORLD_WIDTH; end
  def world_height; WORLD_HEIGHT; end
  def delta_t; DELTA_T; end
  def substeps; $SUBSTEPS; end

  def add_player(conn, player_name)
    player = Player.new(conn, player_name)
    player.generate_id
    player.warp(world_width / 2, world_height / 2) # start in the center of the world
    @space.players.each {|p| p.conn.add_player(player) }
    @space << player
  end

  def delete_player(player)
    puts "Deleting #{player}"
    @space.doom player
    @space.purge_doomed_objects
    @space.players.each {|other| other.conn.delete_player player }
  end

  def create_npc(npc)
    npc = NPC.new(npc['x'], npc['y'])
    npc.generate_id
    @space << npc
    @space.players.each {|p| p.conn.add_npc npc }
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

        # Step the physics environment $SUBSTEPS times each update
        $SUBSTEPS.times do
          @space.update
          server_port.update
        end

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
