$LOAD_PATH << '.'
require 'game'
require 'server_port'
require 'client_engine'
require 'client_connection'

IP_ADDRESS = '1.1.1.1'
CONNECTION_ID = 666

class FakeENetServer
  def initialize(*args)
    $stderr.puts "FakeENetServer.new(#{args.inspect})"
    @queue = []
  end
  def broadcast_packet(data, reliable, channel)
    $stderr.puts "FakeENetServer.broadcast_packet"
    $fake_client.xmit data, channel
  end
  def send_packet(id, data, reliable, channel)
    $fake_client.xmit data, channel
  end
  def update(timeout)
    $stderr.puts "FakeENetServer.update(#{timeout}) - processing #{@queue.size} packets"
    @queue.each do |data, channel|
      $fake_server_port.on_packet_receive(CONNECTION_ID, data, channel)
    end
    @queue.clear
  end
  def on_connection(a_method) # accepts (id, ip)
  end
  def on_packet_receive(a_method) # accepts (id, data, channel)
  end
  def on_disconnection(a_method) # accepts (id)
  end
  def flush
    $stderr.puts "FakeENetServer.flush"
  end

  def xmit(data, channel)
    $stderr.puts "Client->Server on ##{channel}: #{data}"
    @queue << [data, channel]
  end
end

class FakeServerPort < ServerPort
  def _create_enet_server(*args)
    $fake_server_port = self
    $fake_server = FakeENetServer.new *args
  end
end

class FakeGame < Game
  attr_reader :space

  def _create_server_port(*args)
    FakeServerPort.new *args
  end
end

class FakeENetConnection
  def initialize(*args)
    $stderr.puts "FakeENetConnection.new(#{args.inspect})"
    @queue = []
  end
  def connect(timeout)
    $stderr.puts "FakeENetConnection.connect(#{timeout})"
    $fake_server_port.on_connection(CONNECTION_ID, IP_ADDRESS)
    $fake_client_conn.on_connect
  end
  def send_packet(data, reliable, channel)
    $fake_server.xmit data, channel
  end
  def update(timeout)
    $stderr.puts "FakeENetConnection.update(#{timeout}) - processing #{@queue.size} packets"
    @queue.each do |data, channel|
      $fake_client_conn.on_packet(data, channel)
    end
    @queue.clear
  end
  def on_connection(a_method) # accepts no args
  end
  def on_packet_receive(a_method) # accepts (data, channel)
  end
  def on_disconnection(a_method) # accepts no args
  end
  def flush
    $stderr.puts "FakeENetConnection.flush"
  end

  def xmit(data, channel)
    $stderr.puts "Server->Client on ##{channel}: #{data}"
    @queue << [data, channel]
  end
end

class FakeClientConnection < ClientConnection
  def _create_connection(*args)
    $fake_client_conn = self
    $fake_client = FakeENetConnection.new(*args)
  end
end

class FakeGameWindow
  attr_accessor :player_id, :conn, :engine

  def initialize(host, port, player_name)
    @conn = FakeClientConnection.new(host, port, self, player_name)
    @conn.engine = @engine = ClientEngine.new(self)
  end

  def space
    @engine.space
  end

  def player
    space[@player_id]
  end

  def update
    @conn.update
    @engine.update
  end

  def generate_move(move)
    @conn.send_move move
    player.add_move move
  end
end

describe FakeGame do
  let(:hostname) { 'localhost' }
  let(:port_number) { 9998 }
  let(:player_name) { 'Ed' }
  let(:max_clients) { 2 }
  let(:storage) { '.test' }
  let(:level) { 'test-level' }
  let(:cell_width) { 3 }
  let(:cell_height) { 3 }
  let(:self_check) { false }
  let(:profile) { false }

  let(:game) { FakeGame.new(
    port_number, max_clients, storage,
    level, cell_width, cell_height,
    self_check, profile
  ) }
  let(:window) { game; FakeGameWindow.new(hostname, port_number, player_name) }

  it "is in sync after one update" do
    window

    game.update
    window.update

    expect(game.space).to eq(window.space)
  end
end