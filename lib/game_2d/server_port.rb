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
    @player_connections = {}
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
    gone.close
    puts "Remaining connection IDs: #{@clients.keys.sort.join(', ')}"
  end

  def register_player(player_id, conn)
    @player_connections[player_id] = conn
    @new_players << player_id
  end

  def deregister_player(player_id)
    @player_connections.delete player_id
  end

  def new_players
    copy = @new_players.dup
    @new_players.clear
    copy
  end

  def player_connection(player_id)
    @player_connections[player_id]
  end

  # Re-broadcast to everyone except the original sender
  def broadcast_player_action(hash, channel)
    sender_player_id = hash[:player_id]
    fail "No player_id in #{hash.inspect}" unless sender_player_id
    data = hash.to_json
    @player_connections.each do |player_id, conn|
      @server.send_packet(conn.id, data, false, channel) unless player_id == sender_player_id
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
