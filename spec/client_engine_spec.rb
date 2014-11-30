require 'set'
require 'game_2d/game'
require 'game_2d/game_client'
require 'game_2d/server_port'
require 'game_2d/client_engine'
require 'game_2d/client_connection'

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
    @online = false
  end
  def online?; @online; end
  def connect(timeout)
    $stderr.puts "FakeENetConnection.connect(#{timeout})"
    @online = true
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
  include GameClient
  attr_accessor :player_id, :conn, :engine, :text_input

  def initialize(opts = {})
    initialize_from_hash(opts)
    @dialog = nil
    @buttons_down = Set.new
  end

  def _make_client_connection(*args)
    FakeClientConnection.new(*args)
  end

  def display_message(*lines)
    puts lines.collect {|l| "DISPLAY> #{l}"}.join("\n")
  end
  def display_message!(*lines); display_message(*lines); end
  def caption=(c); puts "WINDOW CAPTION => '#{c}'"; end

  def width; SCREEN_WIDTH; end

  def press_button!(button)
    @buttons_down << button
    button_down(button)
  end
  def release_button!(button)
    @buttons_down.delete button
  end

  def button_down?(button)
    @buttons_down.include?(button)
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
  let(:registry_broadcast_every) { nil }
  let(:password_hash) { "0123456789abcdef" }

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
  let(:key_size) { 128 }
  let(:window) {
    game
    w = FakeGameWindow.new(:hostname => hostname, :port => port_number, :name => player_name, :key_size => key_size)
    w.conn.start(password_hash).join
    w
  }

  def update_both
    game.update
#   $stderr.puts "SERVER TICK #{game.tick}"
    window.update
  end

# require 'pry'
  def expect_spaces_to_match
#   [
#     game.space, window.space,
#     game.space.instance_variable_get(:@grid),
#     window.space.instance_variable_get(:@grid)
#   ].pry unless window.space == game.space
    expect(window.space).to eq(game.space)
  end

  it "is in sync after one update" do
    window

    # server sends its public key
    # client sends encrypted password hash
    update_both
    expect(window.space).to be_nil

    # server sends response to login
    update_both

    expect(game.tick).to eq(window.engine.tick)
    expect_spaces_to_match
  end

  def player_on_server
    game.space.players.first
  end

  it "is in sync after a fall and a build" do
    window

    expect(game.tick).to eq(-1)
    expect(window.engine.tick).to be_nil

    # server sends its public key
    # client sends encrypted password hash
    update_both
    expect(window.space).to be_nil

    # server sends response to login in time for tick 1
    27.times do |n|
      update_both
      expect(game.tick).to eq(n+1)
      expect(window.engine.tick).to eq(n+1)
      expect_spaces_to_match
    end

    # Command generated at tick 28, scheduled for tick 34
    window.press_button! Gosu::KbDown

    update_both
    expect_spaces_to_match
    expect(game.space.players.size).to eq(1)
    expect(game.space.npcs.size).to eq(0)

    plr = player_on_server
    expect(plr.y).to eq(800)
    expect(plr.falling?).to be false

    5.times do # ticks 29 - 33
      update_both
      expect_spaces_to_match
      expect(game.space.npcs.size).to eq(0)
    end

    # tick 34
    window.release_button! Gosu::KbDown
    update_both
    expect(game.tick).to eq(34)
    expect(game.space.npcs.size).to eq(1)

    expect_spaces_to_match

    # Command generated at tick 35, scheduled for tick 41
    window.press_button! Gosu::KbUp
    6.times do # ticks 35 - 40
      update_both
      expect_spaces_to_match
      expect(plr.y).to eq(800)
    end
    window.release_button! Gosu::KbUp
    41.times do |n| # ticks 41 - 81
      update_both
      expect(plr.y).to eq(800 - (10 * n))
      cplr = window.engine.space.players.first
      binding.pry unless cplr == plr
      expect(cplr).to eq(plr)
      expect_spaces_to_match
    end
  end

  it "stays in sync during a block-move" do
    window
    update_both
    loop do
      update_both
      break if player_on_server.y == 800
    end

    window.press_button! Gosu::KbDown
    update_both
    window.release_button! Gosu::KbDown
    window.press_button! Gosu::KbLeft

    30.times do
      update_both
    end
    window.release_button! Gosu::KbLeft
    loop do
      update_both
      break if player_on_server.x == 0
    end
    expect_spaces_to_match

  end

end