require 'rubygems'
require 'rev'

$LOAD_PATH << '.'
require 'networking'

HOST = 'localhost'
PORT = 4321

class EchoServerConnection < Networking
  attr_reader :player_name

  def setup(game)
    puts "setup(): #{remote_addr}:#{remote_port} connected.  Waiting for handshake"
    @game = game
  end

  def on_close
    puts "#{object_id} -- #{remote_addr}:#{remote_port} disconnected (delete #{@player_name})"
    @game.remove_player self
  end

  def on_record(hash)
    if hash['handshake']
      @player_name = hash['handshake']['player_name']
      puts "#{object_id} -- #{remote_addr}:#{remote_port} known as #{@player_name}"
      @game.add_player self
      @location = 2
      send_record :location => 2
    else
      @location = hash['location']
      puts "#{@player_name} at #{@location}"
      send_record :location => @location
    end
  end
end

class Game < Rev::TimerWatcher
  def initialize
    super(0.5, true) # Fire event 2 times a second
    @players = []
    attach(Rev::Loop.default)
    @server = Rev::TCPServer.new('localhost', PORT, EchoServerConnection) {|conn| conn.setup self }
    @server.attach(Rev::Loop.default)

    puts "Echo server listening on #{HOST}:#{PORT}"
  end

  def add_player(conn)
    puts "Adding player: #{conn.player_name}"
    @players << conn
    list_players
  end

  def remove_player(conn)
    puts "Removing player: #{conn.player_name}"
    @players.delete conn
    list_players
  end

  def list_players
    puts "Players: #{@players.map(&:player_name).join(', ')}"
  end
end

Game.new
Rev::Loop.default.run
