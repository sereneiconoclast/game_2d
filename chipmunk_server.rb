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
require 'star'

WORLD_WIDTH = 900
WORLD_HEIGHT = 600

PORT = 4321
MAX_CLIENTS = 32

# Tell physics engine to expect 60 updates per second
DELTA_T = 1.0/60.0

# The number of steps to process every Gosu update
# The Player ship can get going so fast as to "move through" a
# star without triggering a collision; an increased number of
# Chipmunk step calls per update will effectively avoid this issue
$SUBSTEPS = 6

# How many cycles between broadcasts of the registry
REGISTRY_BROADCAST_EVERY=60 / 4 # Four times a second

class Game
  def initialize
    # Time increment over which to apply a physics "step"
    @space = GameSpace.new(DELTA_T)

    # This should never happen.  It can only happen client-side because a
    # registry update may delete an object before we get around to it in
    # purge_doomed_objects
    def @space.fire_object_not_found(object)
      raise "Object #{object} not in registry"
    end

    @space.establish_world(world_width, world_height)

    # Here we define what is supposed to happen when a Player (ship) collides with a Star
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @space.add_collision_func(:ship, :star) do |ship_shape, star_shape|
      star = star_shape.body.object
      unless @space.doomed? star # filter out duplicate collisions
        player = ship_shape.body.object
        player.score += 10
        @space.players.each {|p| p.conn.update_score player }
        @space.doom star
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

  def get_all_players
    @space.players
  end

  def get_all_stars
    @space.stars
  end

  def run(server_port)
    loop do
      REGISTRY_BROADCAST_EVERY.times do
        # Send/receive packets for 1/60th second
        server_port.update(1000 / 60)

        # Step the physics environment $SUBSTEPS times each update
        $SUBSTEPS.times { @space.update }

        # Each update (not SUBSTEP) we see if we need to add more Stars
        if rand(100) < 4 and @space.stars.size < 8 then
          star = Star.new(rand * world_width, rand * world_height)
          star.generate_id
          @space << star
          @space.players.each {|p| p.conn.add_star star }
        end

        @space.check_for_registry_leaks
      end # REGISTRY_BROADCAST_EVERY.times

      server_port.broadcast @space.registry
    end # loop
  end

end

game = Game.new

server_port = ServerPort.new(game, PORT, MAX_CLIENTS)

puts "ENet server listening on #{PORT}"
game.run(server_port)
