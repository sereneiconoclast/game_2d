require 'renet'
require 'json'

# The client creates one of these.
# It is then used for all communication with the server.

class ClientConnection < ENet::Connection
  attr_reader :player_name
  attr_accessor :engine

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

    at_tick = hash['at_tick']

    npcs = hash['add_npcs']
    @engine.add_npcs(npcs, at_tick) if npcs

    players = hash['add_players']
    @engine.add_players(players, at_tick) if players

    doomed = hash['delete_entities']
    @engine.delete_entities(doomed, at_tick) if doomed

    score_update = hash['update_score']
    @engine.update_score(score_update, at_tick) if score_update

    registry = hash['registry']
    @engine.sync_registry(registry, at_tick) if registry
  end

  def send_move(at_tick, move, args={})
    return unless move
    args[:move] = move.to_s
    send_record :at_tick => at_tick, :move => args
  end

  def send_create_npc(at_tick, npc)
    send_record(:at_tick => at_tick, :create_npc => npc)
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
