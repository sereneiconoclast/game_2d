require 'networking'

# An instance of this class is created by Rev::TCPServer whenever an
# incoming connection is accepted.

class ServerConnection < Networking

  def setup(game)
    @game = game
    @remote_addr, @remote_port = remote_addr, remote_port
    puts "setup(): #{@remote_addr}:#{@remote_port} connected"
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
    puts "#{@player} logs in from #{@remote_addr}:#{@remote_port}"
    send_record response
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

  def on_close
    puts "#{@player} -- #{@remote_addr}:#{@remote_port} disconnected"
    @game.delete_player @player
  end

  def on_record(data)
    if (handshake = data['handshake'])
      answer_handshake(handshake)
    elsif (move = data['move'])
      @player.add_move move.to_sym
    else
      puts "IGNORING BAD DATA: #{data.inspect}"
    end
  end

  def send_registry(registry)
    send_record :registry => registry
  end
end
