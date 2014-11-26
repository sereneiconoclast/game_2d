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

    response = {
      :you_are => @player_id,
      :world => {
        :world_name => @game.world_name,
        :world_id => @game.world_id,
        :highest_id => @game.world_highest_id,
        :cell_width => @game.world_cell_width,
        :cell_height => @game.world_cell_height,
      },
      :add_players => @game.get_all_players,
      :add_npcs => @game.get_all_npcs,
      :at_tick => @game.tick,
    }
    puts "#{player} logs in from #{@remote_addr} at <#{@game.tick}>"
    send_record response, true # answer login reliably
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
    @game.delete_entity toast
  end

  def on_packet(data, channel)
    hash = JSON.parse(data).fix_keys
    debug_packet('Received', hash)
    if (handshake = hash[:handshake])
      answer_handshake(handshake)
    elsif (password_hash = hash[:password_hash])
      answer_login(password_hash, hash[:iv])
    elsif (hash[:save])
      @game.save
    elsif (ping = hash[:ping])
      answer_ping ping
    else
      @game.add_player_action @player_id, hash
      @port.broadcast_player_action @id,
        hash.merge(:player_id => @player_id),
        channel
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
