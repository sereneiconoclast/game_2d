require 'renet'
require 'json'
require 'server_connection'

class ServerPort
  def initialize(game, port_number, max_clients)
    @game = game
    @server = ENet::Server.new port_number, max_clients, 2, 0, 0
    puts "ENet server listening on #{port_number}"

    @clients = {}
    @player_connections = {}

    @server.on_connection method(:on_connection)
    @server.on_packet_receive method(:on_packet_receive)
    @server.on_disconnection method(:on_disconnection)
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

  def broadcast(data, reliable=false, channel=1)
    @server.broadcast_packet data.to_json, reliable, channel
    @server.flush
  end

  def register_player(player_id, conn)
    @player_connections[player_id] = conn
  end

  def deregister_player(player_id)
    @player_connections.delete player_id
  end

  def player_connection(player_id)
    @player_connections[player_id]
  end

  # Re-broadcast to everyone except the original sender
  def broadcast_player_action(sender_id, data, channel)
    @clients.keys.each do |id|
      @server.send_packet(id, data, false, channel) unless id == sender_id
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
