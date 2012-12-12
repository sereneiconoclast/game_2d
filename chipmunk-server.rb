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
require 'networking'
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

class PlayerConnection < Networking

  def setup(game)
    @game = game
    @remote_addr, @remote_port = remote_addr, remote_port
    puts "setup(): #{@remote_addr}:#{@remote_port} connected"
  end

  def answer_handshake(handshake)
    # Copy this array since it's about to change
    other_players = @game.get_all_players.dup

    player_name = handshake['player_name']
    @player = @game.add_player(self, player_name)

    response = {
      'you_are' => @player,
      'add_players' => other_players,
      'add_stars' => @game.get_all_stars
    }
    puts "#{@player} logs in from #{@remote_addr}:#{@remote_port}"
    send_record response
  end

  def add_star(star)
    send_record 'add_stars' => [ star ]
  end

  def add_player(player)
    send_record 'add_players' => [ player ]
  end

  def delete_player(player)
    send_record 'delete_players' => [ player.registry_id ]
  end

  def update_score(player)
    send_record 'update_score' => { player.registry_id => player.score }
  end

  def on_close
    puts "#{@player} -- #{@remote_addr}:#{@remote_port} disconnected"
    @game.delete_player @player
  end

  def on_record(data)
    if (handshake = data['handshake'])
      answer_handshake(handshake)
    elsif (move = data['move'])
      @player.add_move move.to_sym
    else
      puts "IGNORING BAD DATA: #{data.inspect}"
    end
  end

  def send_registry(registry)
    send_record :registry => registry
  end
end

class RegistryUpdater < Rev::TimerWatcher
  def initialize(game)
    super(0.25, true) # Fire event four times a second
    attach(Rev::Loop.default)
    @game = game
  end

  def on_timer
    @game.send_registry_updates
  end
end

class Game < Rev::TimerWatcher
  def initialize
    super(1.0 / 60.0, true) # Fire event 60 times a second
    attach(Rev::Loop.default)

    # Time increment over which to apply a physics "step" ("delta t")
    @dt = (1.0/60.0)

    # Create our Space and set its damping
    # A damping of 0.8 causes the ship bleed off its force and torque over time
    # This is not realistic behavior in a vacuum of space, but it gives the game
    # the feel I'd like in this situation
    @space = CP::Space.new
    # @space.damping = 0.8
    @space.gravity = CP::Vec2.new(0.0, 10.0)

    # Walls all around the screen
    add_bounding_wall(WORLD_WIDTH / 2, 0.0, WORLD_WIDTH, 0.0)   # top
    add_bounding_wall(WORLD_WIDTH / 2, WORLD_HEIGHT, WORLD_WIDTH, 0.0) # bottom
    add_bounding_wall(0.0, WORLD_HEIGHT / 2, 0.0, WORLD_HEIGHT)   # left
    add_bounding_wall(WORLD_WIDTH, WORLD_HEIGHT / 2, 0.0, WORLD_HEIGHT) # right

    @players = Array.new
    @stars = Array.new

    @registry = {}
    RegistryUpdater.new(self)

    # Here we define what is supposed to happen when a Player (ship) collides with a Star
    # I create a @remove_stars array because we cannot remove either Shapes or Bodies
    # from Space within a collision closure, rather, we have to wait till the closure
    # is through executing, then we can remove the Shapes and Bodies
    # In this case, the Shapes and the Bodies they own are removed in the Gosu::Window.update phase
    # by iterating over the @remove_stars array
    # Also note that both Shapes involved in the collision are passed into the closure
    # in the same order that their collision_types are defined in the add_collision_func call
    @remove_stars = []
    @space.add_collision_func(:ship, :star) do |ship_shape, star_shape|
      star = star_shape.body.object
      unless @remove_stars.include? star # filter out duplicate collisions
        player = ship_shape.body.object
        player.score += 10
        @players.each {|p| p.conn.update_score player }
        @remove_stars << star
        # remember to return 'true' if we want regular collision handling
      end
    end
  end

  def add_bounding_wall(x_pos, y_pos, width, height)
    wall = CP::Body.new_static
    wall.p = CP::Vec2.new(x_pos, y_pos)
    wall.v = CP::Vec2.new(0.0, 0.0)
    wall.v_limit = 0.0 # max velocity (never move)
    shape = CP::Shape::Segment.new(wall,
      CP::Vec2.new(-0.5 * width, -0.5 * height),
      CP::Vec2.new(0.5 * width, 0.5 * height),
      1.0) # thickness
    shape.collision_type = :wall
    shape.e = 0.99 # elasticity (bounce)
    @space.add_body(wall)
    @space.add_shape(shape)
  end

  def add_player(conn, player_name)
    player = Player.new(conn, player_name)
    player.generate_id
    @space.add_body(player.body)
    @space.add_shape(player.shape)
    player.warp(WORLD_WIDTH / 2, WORLD_HEIGHT / 2) # start in the center of the world
    @players.each {|p| p.conn.add_player(player) }
    @players << player
    @registry[player.registry_id] = player
    player
  end

  def delete_player(player)
    puts "Deleting #{player}"
    @players.delete player
    @registry.delete player.registry_id
    @space.remove_body player.body
    @space.remove_shape player.shape
    @players.each {|other| other.conn.delete_player player }
  end

  def get_all_players
    @players
  end

  def get_all_stars
    @stars
  end

  def on_timer
    # Step the physics environment $SUBSTEPS times each update
    $SUBSTEPS.times do
      @remove_stars.each do |star|
        @stars.delete star
        @space.remove_body(star.body)
        @space.remove_shape(star.shape)
        raise "Star #{star} not in registry" unless @registry.delete star.registry_id
      end
      @remove_stars.clear # clear out the stars for next pass

      # When a force or torque is set on a Body, it is cumulative
      # This means that the force you applied last SUBSTEP will compound with the
      # force applied this SUBSTEP; which is probably not the behavior you want
      # We reset the forces on the Player each SUBSTEP for this reason
      @players.each &:dequeue_move

      # Perform the step over @dt period of time
      # For best performance @dt should remain consistent for the game
      @space.step(@dt)
    end

    # Each update (not SUBSTEP) we see if we need to add more Stars
    if rand(100) < 4 and @stars.size < 8 then
      star = Star.new(rand * WORLD_WIDTH, rand * WORLD_HEIGHT)
      star.generate_id
      @space.add_body(star.body)
      @space.add_shape(star.shape)
      @stars << star
      @registry[star.registry_id] = star
      @players.each {|p| p.conn.add_star star }
    end

    # Check for registry leaks
    expected = @players.size + @stars.size
    actual = @registry.size
    if expected != actual
      puts "We have #{expected} game objects, #{actual} in registry (delta: #{actual - expected})"
    end
  end

  def send_registry_updates
    @players.each do |p|
      p.conn.send_registry(@registry)
    end
  end
end

game = Game.new

server = Rev::TCPServer.new(HOSTNAME, PORT, PlayerConnection) {|conn| conn.setup(game) }
server.attach(Rev::Loop.default)

puts "Rev server listening on #{HOSTNAME}:#{PORT}"
Rev::Loop.default.run
