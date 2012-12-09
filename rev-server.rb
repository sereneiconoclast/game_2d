require 'rubygems'
require 'rev'

HOST = 'localhost'
PORT = 4321

class EchoServerConnection < Rev::TCPSocket
  def on_connect
    puts "#{object_id} -- #{remote_addr}:#{remote_port} connected"
  end

  def on_close
    puts "#{object_id} -- #{remote_addr}:#{remote_port} disconnected"
  end

  def on_read(data)
    write data
    puts "#{object_id} -- #{remote_addr}:#{remote_port} sent '#{data.chomp}'"
  end
end

server = Rev::TCPServer.new('localhost', PORT, EchoServerConnection)
server.attach(Rev::Loop.default)

puts "Echo server listening on #{HOST}:#{PORT}"
Rev::Loop.default.run
