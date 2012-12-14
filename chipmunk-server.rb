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
require 'server_connection'
require 'game_space'
require 'player'
require 'star'

WORLD_WIDTH = 900
WORLD_HEIGHT = 600

HOSTNAME = 'localhost'
PORT = 4321

# The number of steps to process every Gosu update
# The Player ship can get going so fast as to "move through" a
# star without triggering a collision; an increased number of
# Chipmunk step calls per update will effectively avoid this issue
$SUBSTEPS = 6

class Game < Rev::TimerWatcher
  def initialize
    super(1.0 / 60.0, true) # Fire event 60 times a second.  TODO: Constant
    attach(Rev::Loop.default)

    # Time increment over which to apply a physics "step" ("delta t")
    @space = GameSpace.new(1.0/60.0) # TODO: Constant
    @space.establish_world(world_width, world_height)

    @space.send_registry_updates_every(0.25) # Four times a second.  TODO: Constant

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

  def on_timer
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
  end
end

game = Game.new

server = Rev::TCPServer.new(HOSTNAME, PORT, ServerConnection) {|conn| conn.setup(game) }
server.attach(Rev::Loop.default)

puts "Rev server listening on #{HOSTNAME}:#{PORT}"
Rev::Loop.default.run
