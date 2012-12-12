require 'networking'

# The client calls ClientConnection.connect() to create one of these.
# It is then used for all communication between them.

class ClientConnection < Networking
  attr_reader :player_name

  def self.connect(host, port, *args)
    super
  end

  def setup(game, player_name)
    @game = game
    @player_name = player_name
    self
  end

  def on_connect
    super
    puts "Connected to server #{remote_addr}:#{remote_port}; sending handshake"
    send_record :handshake => { :player_name => @player_name }
  end

  def on_close
    puts "Client disconnected"
    @game.close
  end

  def on_record(hash)
    handshake_response = hash['you_are']
    if handshake_response
      @game.create_local_player handshake_response
    end

    stars = hash['add_stars']
    @game.add_stars(stars) if stars

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
end
