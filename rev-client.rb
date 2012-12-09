require 'rubygems'
require 'rev'

$LOAD_PATH << '.'
require 'networking'

HOST = 'localhost'
PORT = 4321

class EchoClientConnection < Networking
  def self.connect(host, port, *args)
    super
  end

  def on_connect
    super
    puts "#{object_id} -- #{remote_addr}:#{remote_port} connected"
    send_record :handshake => { :player_name => 'Fred' }
  end

  def on_close
    puts "Client disconnected"
    exit 0
  end

  def on_record(hash)
    @location = hash['location']
    puts "Located at #{@location}"
    if @location > 6
      close
    else
      @location += 1
      send_record :location => @location
    end
  end
end

EchoClientConnection.connect('localhost', PORT).attach(Rev::Loop.default)

Rev::Loop.default.run
