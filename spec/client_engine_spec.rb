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
  attr_accessor :player_id, :conn, :engine, :text_input, :mouse_x, :mouse_y

  def initialize(opts = {})
    initialize_from_hash(opts)
    @mouse_x = @mouse_y = @camera_x = @camera_y = 0
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
  let(:key_size) { 256 }
  let(:window) {
    game
    w = FakeGameWindow.new(:hostname => hostname, :port => port_number, :name => player_name, :key_size => key_size)
    w.conn.start(password_hash).join
    w
  }

  def update_both
    game.update
#   $stderr.puts "SERVER updated, TICK #{game.tick}"
    window.update
#   $stderr.puts "CLIENT updated"
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

  it "is in sync after a fall, slide left, and build" do
    window

    expect(game.tick).to eq(-1)
    expect(window.engine.tick).to be_nil

    # server sends its public key
    # client sends encrypted password hash
    update_both
    expected_tick = 0
    expect(game.tick).to eq(expected_tick)
    expect(window.space).to be_nil
    expect(game.space.players.size).to eq(0)
    expect(game.space.npcs.size).to eq(1) # the starter Base

    # server sends response to login in time for tick 1
    # The base is still falling, and the player falls with it
    loop do
      update_both
      expected_tick += 1
      expect(game.tick).to eq(expected_tick)
      expect(window.engine.tick).to eq(expected_tick)
      expect_spaces_to_match
      expect(game.space.players.size).to eq(1)
      expect(game.space.npcs.size).to eq(1)
      break if player_on_server.y == 800
      expect(player_on_server.should_fall?).to be true
    end
    expect(player_on_server.should_fall?).to be false

    # We can't build where the base is
    # So slide into the space on the left
    window.press_button! Gosu::KbLeft
    27.times do
      update_both
      expect_spaces_to_match
    end
    window.release_button! Gosu::KbLeft
    loop do
      update_both
      expect_spaces_to_match
      break if player_on_server.x == 0
    end

    window.press_button! Gosu::KbDown

    update_both
    expect_spaces_to_match
    # Does not take effect immediately, but only after 6 ticks
    expect(game.space.npcs.size).to eq(1) # the starter Base
    window.release_button! Gosu::KbLeft

    5.times do # waiting for the 6-tick delay to transpire
      update_both
      expect_spaces_to_match
      expect(game.space.npcs.size).to eq(1)
    end

    update_both
    expect(game.space.npcs.size).to eq(2)

    expect_spaces_to_match

    window.press_button! Gosu::KbUp
    6.times do # waiting for this command to go through
      update_both
      expect_spaces_to_match
      expect(player_on_server.y).to eq(800)
    end
    window.release_button! Gosu::KbUp
    41.times do |n|
      update_both
      expect(player_on_server.y).to eq(800 - (10 * n))
      cplr = window.engine.space.players.first
      binding.pry unless cplr == player_on_server
      expect(cplr).to eq(player_on_server)
      expect_spaces_to_match
    end
  end

  it "stays in sync during a base-move" do
    window
    update_both
    loop do
      update_both
      break if player_on_server.y == 800
    end

    window.press_button! Gosu::KbLeft
    27.times { update_both }
    window.release_button! Gosu::KbLeft

    loop do
      update_both
      break if player_on_server.x == 0
    end
    expect_spaces_to_match

    base = window.engine.space.npcs.first
    expect([base.x, base.y]).to eq([400,800])

    window.mouse_x, window.mouse_y = 50, 90
    expect(window.mouse_entity_location).to eq([300, 700])

    window.press_button! Gosu::MsRight
    update_both
    window.release_button! Gosu::MsRight
    expect_spaces_to_match

    in_a_row = 0
    99.times do |n|
      update_both
      expect_spaces_to_match

      base = window.engine.space.npcs.first
      $stderr.puts "step ##{n}: base is at #{base.x},#{base.y} moving #{base.x_vel},#{base.y_vel}"
      if base.x == 300 && base.y == 700
        in_a_row += 1
      else
        in_a_row = 0
      end
      break if in_a_row > 3
    end
    expect(in_a_row).to eq(4)
  end

end