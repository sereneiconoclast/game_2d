require 'renet'
require 'json'
require 'server_connection'

class ServerPort
  def initialize(game, port, max_clients)
    @game = game
    @server = ENet::Server.new port, max_clients, 2, 0, 0
    @clients = {}

    @server.on_connection method(:on_connection)
    @server.on_packet_receive method(:on_packet_receive)
    @server.on_disconnection method(:on_disconnection)
  end

  def on_connection(id, ip)
    puts "New ENet connection #{id} from #{ip}"
    @clients[id] = ServerConnection.new(@game, @server, id, ip)
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

  def update(timeout=0) # non-blocking by default
    @server.update(timeout)
  end
end
