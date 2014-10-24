require 'json'

# An instance of this class is created by ServerPort whenever an
# incoming connection is accepted.

class ServerConnection

  def initialize(game, server, id, remote_addr)
    @game, @server, @id, @remote_addr = game, server, id, remote_addr
    puts "ServerConnection: New connection #{id} from #{remote_addr}"
  end

  def answer_handshake(handshake)
    # Copy this array since it's about to change
    other_players = @game.get_all_players.dup

    player_name = handshake['player_name']
    @player = @game.add_player(self, player_name)

    response = {
      'you_are' => @player,
      'world' => {
        :cell_width => @game.world_cell_width,
        :cell_height => @game.world_cell_height,
      },
      'add_players' => other_players,
      'add_npcs' => @game.get_all_npcs,
    }
    puts "#{@player} logs in from #{@remote_addr}"
    send_record response, true # answer handshake reliably
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
    puts "#{@player} -- #{@remote_addr} disconnected"
    @game.delete_entity @player
  end

  def on_packet(data, channel)
    hash = JSON.parse data
    if (handshake = hash['handshake'])
      answer_handshake(handshake)
    elsif (move = hash['move'])
      @player.add_move move
    elsif (npc = hash['create_npc'])
      @game.create_npc npc
    elsif (hash['save'])
      @game.save
    elsif (ping = hash['ping'])
      answer_ping ping
    else
      puts "IGNORING BAD DATA: #{hash.inspect}"
    end
  end

  def send_registry(registry)
    send_record :registry => registry
  end

  def send_record(hash, reliable=false, channel=0)
    send_str = hash.to_json
    # Send data to the client (client ID, data, reliable or not, channel ID)
    @server.send_packet(@id, send_str, reliable, channel)
    @server.flush
  end
end
