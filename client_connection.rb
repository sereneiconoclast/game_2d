require 'renet'
require 'json'

# The client creates one of these.
# It is then used for all communication with the server.

class ClientConnection < ENet::Connection
  attr_reader :player_name

  def initialize(host, port, game, player_name, timeout=2000)
    # remote host address, remote host port, channels, download bandwidth, upload bandwidth
    super(host, port, 2, 0, 0)
    @game = game
    @player_name = player_name

    on_connection(method(:on_connect))
    on_disconnection(method(:on_close))
    on_packet_receive(method(:on_packet))

    connect(timeout)
  end

  def on_connect
    puts "Connected to server - sending handshake"
    # send handshake reliably
    send_record( { :handshake => { :player_name => @player_name } }, true)
  end

  def on_close
    puts "Client disconnected by server"
    @game.shutdown
  end

  def on_packet(data, channel)
    hash = JSON.parse data

    world = hash['world']
    if world
      @game.establish_world(world)
    end

    handshake_response = hash['you_are']
    if handshake_response
      @game.create_local_player handshake_response
    end

    stars = hash['add_stars']
    @game.add_stars(stars) if stars

    players = hash['add_players']
    @game.add_players(players) if players

    players = hash['delete_players']
    @game.delete_players(players) if players

    score_update = hash['update_score']
    @game.update_score(score_update) if score_update

    registry = hash['registry']
    @game.sync_registry(registry) if registry
  end

  def send_move(move)
    send_record(:move => move.to_s) if move
  end

  def send_record(data, reliable=false)
    send_packet(data.to_json, reliable, 0)
    flush
  end
end
