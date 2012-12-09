require 'rubygems'
require 'rev'

HOST = 'localhost'
PORT = 4321

class EchoClientConnection < Rev::TCPSocket
  def self.connect(host, port, *args)
    super
  end

  def on_connect
    puts "#{object_id} -- #{remote_addr}:#{remote_port} connected"
    write "Hello, I am a client"
  end

  def on_close
    puts "#{object_id} -- #{remote_addr}:#{remote_port} disconnected"
    exit 0
  end

  def on_read(data)
    puts "Got: #{data}"
    close
  end
end

EchoClientConnection.connect('localhost', PORT).attach(Rev::Loop.default)

Rev::Loop.default.run
