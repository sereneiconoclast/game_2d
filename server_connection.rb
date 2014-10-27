require 'json'

# An instance of this class is created by ServerPort whenever an
# incoming connection is accepted.

class ServerConnection

  def initialize(port, game, server, id, remote_addr)
    @port, @game, @server, @id, @remote_addr = port, game, server, id, remote_addr
    puts "ServerConnection: New connection #{id} from #{remote_addr}"
  end

  def answer_handshake(handshake)
    # Copy this array since it's about to change
    other_players = @game.get_all_players.dup

    player_name = handshake['player_name']
    player = @game.add_player(player_name)
    @player_id = player.registry_id
    @port.register_player @player_id, self

    response = {
      'you_are' => player,
      'world' => {
        :cell_width => @game.world_cell_width,
        :cell_height => @game.world_cell_height,
      },
      'add_players' => other_players,
      'add_npcs' => @game.get_all_npcs,
      'tick' => @game.tick,
    }
    puts "#{player} logs in from #{@remote_addr} at <#{@game.tick}>"
    send_record response, true # answer handshake reliably
  end

  def player
    @game[@player_id]
  end

  def answer_ping(ping)
    send_record :pong => ping
  end

  def add_npc(npc)
    send_record 'add_npcs' => [ npc ]
  end

  def add_player(player)
    send_record 'add_players' => [ player ]
  end

  def delete_entity(entity)
    send_record 'delete_entities' => [ entity.registry_id ]
  end

  def update_score(player)
    send_record 'update_score' => { player.registry_id => player.score }
  end

  def close
    @port.deregister_player @player_id
    toast = player
    puts "#{toast} -- #{@remote_addr} disconnected at <#{@game.tick}>"
    @game.delete_entity toast
  end

  def on_packet(data, channel)
    hash = JSON.parse data
    if (handshake = hash['handshake'])
      answer_handshake(handshake)
    elsif (hash['save'])
      @game.save
    elsif (ping = hash['ping'])
      answer_ping ping
    else
      @game.add_player_action @player_id, hash
      @port.broadcast_player_action @id, data, channel
    end
  end

  def send_registry(registry)
    send_record :registry => registry, :tick => @game.tick
  end

  def send_record(hash, reliable=false, channel=0)
    send_str = hash.to_json
    # Send data to the client (client ID, data, reliable or not, channel ID)
    @server.send_packet(@id, send_str, reliable, channel)
    @server.flush
  end
end
