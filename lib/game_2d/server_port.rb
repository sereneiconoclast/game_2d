require 'set'
require 'renet'
require 'json'
require 'game_2d/server_connection'

class ServerPort
  def initialize(game, port_number, max_clients)
    @game = game
    @server = _create_enet_server port_number, max_clients, 2, 0, 0
    puts "ENet server listening on #{port_number}"

    @clients = {}
    @player_connections = {} # player_name => ServerConnection
    @new_players = Set.new

    @server.on_connection method(:on_connection)
    @server.on_packet_receive method(:on_packet_receive)
    @server.on_disconnection method(:on_disconnection)
  end

  def _create_enet_server(*args)
    ENet::Server.new *args
  end

  def on_connection(id, ip)
    puts "New ENet connection #{id} from #{ip}"
    @clients[id] = ServerConnection.new(self, @game, @server, id, ip)
  end

  def on_packet_receive(id, data, channel)
    @clients[id].on_packet(data, channel)
  end

  def on_disconnection(id)
    puts "ENet connection #{id} disconnected"
    gone = @clients.delete id
    deregister_player(gone)
    puts "Remaining connection IDs: #{@clients.keys.sort.join(', ')}"
  end

  def register_player(player_name, conn)
    if old_conn = @player_connections[player_name]
      warn "Disconnecting old connection for #{player_name} (#{old_conn})"
      old_conn.disconnect!
    end
    @player_connections[player_name] = conn
    @new_players << player_name
  end

  def deregister_player(conn)
    player_name = conn.player_name
    if conn.authenticated? && @player_connections[player_name] == conn
      puts "Player #{player_name} logged out at <#{@game.tick}>"
      @player_connections.delete player_name
      conn.close
    end
  end

  def new_players
    copy = @new_players.dup
    @new_players.clear
    copy
  end

  def player_name_connection(player_name)
    @player_connections[player_name]
  end

  # Re-broadcast to everyone except the original sender
  def broadcast_player_action(hash, channel=0)
    sender_player_name = hash[:player_name]
    fail "No player_name in #{hash.inspect}" unless sender_player_name
    data = hash.to_json
    @player_connections.each do |player_name, conn|
      @server.send_packet(conn.id, data, false, channel) unless player_name == sender_player_name
    end
    @server.flush
  end

  def update(timeout=0) # non-blocking by default
    @server.update(timeout)
  end

  def update_until(stop_time)
    while Time.now.to_r < stop_time do
      update
    end
  end
end
