require 'renet'
require 'json'
require 'base64'
require 'openssl'
require 'game_2d/hash'
require 'game_2d/encryption'

# The client creates one of these.
# It is then used for all communication with the server.

class ClientConnection
  include Encryption
  include Base64

  attr_reader :player_name
  attr_accessor :engine

  # We tell the server to execute all actions this many ticks
  # in the future, to give the message time to propagate around
  # the fleet
  ACTION_DELAY = 6 # 1/10 of a second

  def initialize(host, port, game, player_name, key_size, timeout=2000)
    # remote host address, remote host port, channels, download bandwidth, upload bandwidth
    @socket = _create_connection(host, port, 2, 0, 0)
    @host, @port, @game, @player_name, @key_size, @timeout =
     host,  port,  game,  player_name,  key_size,  timeout

    @socket.on_connection(method(:on_connect))
    @socket.on_disconnection(method(:on_close))
    @socket.on_packet_receive(method(:on_packet))

    @dh = @password_hash = nil
  end

  def start(password_hash)
    @password_hash = password_hash
    Thread.new do
      @game.display_message! "Establishing encryption (#{@key_size}-bit)..."
      @dh = OpenSSL::PKey::DH.new(@key_size)

      # Connect to server and kick off handshaking
      # We will create our player object only after we've been accepted by the server
      # and told our starting position
      @game.display_message! "Connecting to #{@host}:#{@port} as #{@player_name}"
      @socket.connect(@timeout)
    end
  end

  def _create_connection(*args)
    ENet::Connection.new(*args)
  end

  def on_connect
    @game.display_message "Connected, logging in"
    send_record( { :handshake => {
      :player_name => @player_name,
      :dh_public_key => @dh.public_key.to_pem,
      :client_public_key => @dh.pub_key.to_s
    } }, true) # send handshake reliably
  end

  def login(server_public_key)
    self.key = @dh.compute_key(OpenSSL::BN.new server_public_key)
    data, iv = encrypt(@password_hash)
    @password_hash = nil
    send_record(
      :password_hash => strict_encode64(data),
      :iv => strict_encode64(iv)
    )
  end

  def on_close
    puts "Client disconnected by server"
    @game.shutdown
  end

  def on_packet(data, channel)
    hash = JSON.parse(data).fix_keys
    debug_packet('Received', hash)

    if pong = hash.delete(:pong)
      stop = Time.now.to_f
      puts "Ping took #{stop - pong[:start]} seconds"
    end

    if server_public_key = hash.delete(:server_public_key)
      login(server_public_key)
      return
    end

    fail "No at_tick in #{hash.inspect}" unless at_tick = hash.delete(:at_tick)

    if world = hash.delete(:world)
      @game.clear_message
      @engine.establish_world(world, at_tick)
    end

    you_are = hash.delete :you_are
    registry, highest_id = hash.delete(:registry), hash.delete(:highest_id)

    delta_keys = [
      :add_players, :add_npcs, :delete_entities, :update_entities, :update_score, :move
    ]
    @engine.add_delta(hash) if delta_keys.any? {|k| hash.has_key? k}

    if you_are
      # The 'world' response includes deltas for add_players and add_npcs
      # Need to process those first, as one of the players is us
      @engine.apply_deltas(at_tick)

      @engine.create_local_player you_are
    end

    @engine.sync_registry(registry, highest_id, at_tick) if registry
  end

  def send_actions_at
    @engine.tick + ACTION_DELAY
  end

  def send_move(move, args={})
    return unless move && online?
    args[:move] = move.to_s
    delta = { :at_tick => send_actions_at, :move => args }
    send_record delta
    delta[:player_id] = @engine.player_id
    @engine.add_delta delta
  end

  def send_create_npc(npc)
    return unless online?
    # :on_* hooks are for our own use; we don't send them
    remote_npc = npc.reject {|k,v| k.to_s.start_with? 'on_'}
    send_record :at_tick => send_actions_at, :add_npcs => [ remote_npc ]
    @engine.add_delta :at_tick => send_actions_at, :add_npcs => [ npc ]
  end

  def send_update_entity(entity)
    return unless online?
    delta = { :update_entities => [entity], :at_tick => send_actions_at }
    send_record delta
    @engine.add_delta delta
  end

  def send_save
    send_record :save => true
  end

  def send_ping
    send_record :ping => { :start => Time.now.to_f }
  end

  def send_record(data, reliable=false)
    return unless online?
    debug_packet('Sending', data)
    @socket.send_packet(data.to_json, reliable, 0)
    @socket.flush
  end

  def debug_packet(direction, hash)
    return unless $debug_traffic
    at_tick = hash[:at_tick] || 'NO TICK'
    keys = hash.keys - [:at_tick]
    puts "#{direction} #{keys.join(', ')} <#{at_tick}>"
  end

  def update
    @socket.update(0) # non-blocking
  end

  def online?; @socket.online?; end
  def disconnect; @socket.disconnect(200) if online?; end
end
