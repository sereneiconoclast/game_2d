require 'json'
require 'base64'
require 'openssl'
require 'game_2d/hash'
require 'game_2d/encryption'

# An instance of this class is created by ServerPort whenever an
# incoming connection is accepted.

class ServerConnection
  include Encryption
  include Base64

  def initialize(port, game, server, id, remote_addr)
    @port, @game, @server, @id, @remote_addr = port, game, server, id, remote_addr
    puts "ServerConnection: New connection #{id} from #{remote_addr}"
  end

  attr_reader :id, :player_id

  def answer_handshake(handshake)
    @player_name = handshake[:player_name]
    dh_public_key = handshake[:dh_public_key]
    client_public_key = handshake[:client_public_key]
    dh = OpenSSL::PKey::DH.new(dh_public_key)
    dh.generate_key!
    self.key = dh.compute_key(OpenSSL::BN.new client_public_key)
    response = {
      :server_public_key => dh.pub_key.to_s
    }
    send_record response, true # answer reliably
  end

  def answer_login(b64_password_hash, b64_iv)
    password_hash = decrypt(
      strict_decode64(b64_password_hash),
      strict_decode64(b64_iv))
    player_data = @game.player_data(@player_name)
    if player_data
      unless password_hash == player_data[:password_hash]
        $stderr.puts "Wrong password for #{@player_name} (#{password_hash} != #{player_data[:password_hash]})"
        disconnect!
        return
      end
    else # new player
      @game.store_player_data @player_name, :password_hash => password_hash
    end

    player = @game.add_player(@player_name)
    @player_id = player.registry_id
    @port.register_player @player_id, self
    puts "#{player} logs in from #{@remote_addr} at <#{@game.tick}>"

    # We don't send the registry here.  The Game will do it after
    # all logins have been processed and the update has completed.
    # Otherwise, we're sending an incomplete frame.
  end

  def player
    @game[@player_id]
  end

  def answer_ping(ping)
    send_record :pong => ping
  end

  def add_npc(npc, at_tick)
    send_record :add_npcs => [ npc ], :at_tick => at_tick
  end

  def add_player(player, at_tick)
    send_record :add_players => [ player ], :at_tick => at_tick
  end

  def delete_entity(entity, at_tick)
    send_record :delete_entities => [ entity.registry_id ], :at_tick => at_tick
  end

  def update_entities(entities, at_tick)
    send_record :update_entities => entities, :at_tick => at_tick
  end

  # Not called yet...
  def update_score(player, at_tick)
    send_record :update_score => { player.registry_id => player.score }, :at_tick => at_tick
  end

  def close
    return unless @player_id
    @port.deregister_player @player_id
    toast = player
    puts "#{toast} -- #{@remote_addr} disconnected at <#{@game.tick}>"
    @game.send_player_gone toast
  end

  def on_packet(data, channel)
    hash = JSON.parse(data).fix_keys
    debug_packet('Received', hash)
    if handshake = hash.delete(:handshake)
      answer_handshake(handshake)
    elsif password_hash = hash.delete(:password_hash)
      answer_login(password_hash, hash.delete(:iv))
    elsif hash.delete(:save)
      @game.save
    elsif ping = hash.delete(:ping)
      answer_ping ping
    else
      if hash[:player_id] = @player_id
        @game.add_player_action hash
        # TODO: Validate
        @port.broadcast_player_action hash, channel
      else
        $stderr.puts "Ignoring move #{hash.inspect}, no player_id for this connection"
      end
    end
  end

  def send_record(hash, reliable=false, channel=0)
    debug_packet('Sending', hash)
    send_str = hash.to_json
    # Send data to the client (client ID, data, reliable or not, channel ID)
    @server.send_packet(@id, send_str, reliable, channel)
    @server.flush
  end

  def debug_packet(direction, hash)
    return unless $debug_traffic
    at_tick = hash[:at_tick] || 'NO TICK'
    keys = hash.keys - [:at_tick]
    puts "#{direction} #{keys.join(', ')} <#{at_tick}>"
  end

  def disconnect!
    @server.disconnect_client(@id)
  end
end
