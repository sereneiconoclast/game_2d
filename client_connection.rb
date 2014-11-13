require 'renet'
require 'json'

# The client creates one of these.
# It is then used for all communication with the server.

class ClientConnection
  attr_reader :player_name
  attr_accessor :engine

  # We tell the server to execute all actions this many ticks
  # in the future, to give the message time to propagate around
  # the fleet
  ACTION_DELAY = 6 # 1/10 of a second

  def initialize(host, port, game, player_name, timeout=2000)
    # remote host address, remote host port, channels, download bandwidth, upload bandwidth
    @socket = _create_connection(host, port, 2, 0, 0)
    @game = game
    @player_name = player_name

    @socket.on_connection(method(:on_connect))
    @socket.on_disconnection(method(:on_close))
    @socket.on_packet_receive(method(:on_packet))

    @socket.connect(timeout)
  end

  def _create_connection(*args)
    ENet::Connection.new(*args)
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
    debug_packet('Received', hash)

    pong = hash['pong']
    if pong
      stop = Time.now.to_f
      puts "Ping took #{stop - pong['start']} seconds"
    end

    at_tick = hash['at_tick']
    fail "No at_tick in #{hash.inspect}" unless at_tick

    world = hash['world']
    if world
      @engine.establish_world(world, at_tick)
    end

    delta_keys = %w(
      add_players add_npcs delete_entities update_entities update_score move
    )
    @engine.add_delta(hash) if delta_keys.any? {|k| hash.has_key? k}

    you_are = hash['you_are']
    if you_are
      # The 'world' response includes deltas for add_players and add_npcs
      # Need to process those first, as one of the players is us
      @engine.apply_all_deltas(at_tick)

      @engine.create_local_player you_are
    end

    registry = hash['registry']
    @engine.sync_registry(registry, at_tick) if registry
  end

  def send_actions_at
    @engine.tick + ACTION_DELAY
  end

  def send_move(move, args={})
    return unless move
    args[:move] = move.to_s
    send_record :at_tick => send_actions_at, :move => args
  end

  def send_create_npc(npc)
    send_record(:at_tick => send_actions_at, :create_npc => npc)
  end

  def send_save
    send_record :save => true
  end

  def send_ping
    send_record :ping => { :start => Time.now.to_f }
  end

  def send_record(data, reliable=false)
    debug_packet('Sending', data)
    @socket.send_packet(data.to_json, reliable, 0)
    @socket.flush
  end

  def debug_packet(direction, hash)
    return unless $debug_traffic
    at_tick = hash['at_tick'] || hash[:at_tick] || 'NO TICK'
    keys = hash.keys - ['at_tick', :at_tick]
    puts "#{direction} #{keys.join(', ')} <#{at_tick}>"
  end

  def update
    @socket.update(0) # non-blocking
  end

  def online?; @socket.online?; end
  def disconnect; @socket.disconnect(200); end
end
