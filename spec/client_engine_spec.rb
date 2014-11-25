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
    :port                     => port_number,
    :max_clients              => max_clients,
    :storage                  => storage,
    :level                    => level,
    :width                    => cell_width,
    :height                   => cell_height,
    :self_check               => self_check,
    :profile                  => profile,
    :registry_broadcast_every => registry_broadcast_every
  ) }
  let(:window) { game; FakeGameWindow.new(hostname, port_number, player_name) }

  def update_both
    game.update
    window.update
  end

  def expect_spaces_to_match
    expect(window.space).to eq(game.space)
  end

  context "with default registry syncs" do
    let(:registry_broadcast_every) { nil }
    it "is in sync after one update" do
      window

      update_both

      expect_spaces_to_match
    end
    it "is in sync after a fall and a build" do
      window

      expect(game.tick).to eq(-1)
      expect(window.engine.tick).to be_nil

      28.times do |n|
        update_both
        expect(game.tick).to eq(n)
        expect(window.engine.tick).to eq(n)
        expect_spaces_to_match
      end

      expect(game.space.players.size).to eq(1)
      expect(game.space.npcs.size).to eq(0)

      plr = game.space.players.first
      expect(plr.y).to eq(800)

      # Command generated at tick 27, scheduled for tick 33
      window.generate_move :build

      5.times do # ticks 28 - 32
        update_both
        expect_spaces_to_match
        expect(game.space.npcs.size).to eq(0)
      end

      # tick 33
      update_both
      expect(game.tick).to eq(33)
      expect(game.space.npcs.size).to eq(1)

      expect_spaces_to_match

      # Command generated at tick 33, scheduled for tick 39
      window.generate_move :rise_up
      5.times do # ticks 34 - 38
        update_both
        $stderr.puts "TICK ##{game.tick}"
        expect_spaces_to_match
        expect(plr.y).to eq(800)
      end
      41.times do |n| # ticks 39 - 79
        update_both
        $stderr.puts "TICK ##{game.tick}"
        expect(plr.y).to eq(800 - (10 * n))
        cplr = window.engine.space.players.first
        binding.pry unless cplr == plr
        expect(cplr).to eq(plr)
        expect_spaces_to_match
      end
    end
  end
  context "with no registry syncs" do
    let(:registry_broadcast_every) { 0 }
    it "is in sync after one update" do
      window
      update_both

      expect_spaces_to_match
    end
  end
end