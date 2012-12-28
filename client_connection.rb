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

    pong = hash['pong']
    if pong
      stop = Time.now.to_f
      puts "Ping took #{stop - pong['start']} seconds"
    end

    world = hash['world']
    if world
      @game.establish_world(world)
    end

    handshake_response = hash['you_are']
    if handshake_response
      @game.create_local_player handshake_response
    end

    npcs = hash['add_npcs']
    @game.add_npcs(npcs) if npcs

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

  def send_create_npc(npc)
    send_record(:create_npc => npc)
  end

  def send_save
    send_record :save => true
  end

  def send_ping
    send_record :ping => { :start => Time.now.to_f }
  end

  def send_record(data, reliable=false)
    send_packet(data.to_json, reliable, 0)
    flush
  end
end
