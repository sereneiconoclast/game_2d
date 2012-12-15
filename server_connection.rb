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
        :width => @game.world_width,
        :height => @game.world_height,
        :delta_t => @game.delta_t,
        :substeps => @game.substeps,
      },
      'add_players' => other_players,
      'add_stars' => @game.get_all_stars
    }
    puts "#{@player} logs in from #{@remote_addr}"
    send_record response, true # answer handshake reliably
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

  def close
    puts "#{@player} -- #{@remote_addr} disconnected"
    @game.delete_player @player
  end

  def on_packet(data, channel)
    hash = JSON.parse data
    if (handshake = hash['handshake'])
      answer_handshake(handshake)
    elsif (move = hash['move'])
      @player.add_move move.to_sym
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
  end
end
