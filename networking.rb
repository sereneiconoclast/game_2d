require 'json'
require 'rev'

class Networking < Rev::TCPSocket

  # Can be overridden, but subclass must call super
  def on_connect
    puts "Establishing network_buffer and record"
    @network_buffer = ''
    @last_record = nil
    sync = true
  end

  def send_record(hash)
    send_str = hash.to_json
    len = send_str.size
    # puts "Sending: #{send_str} (size: #{len})"
    write([len].pack "N")# 32-bit unsigned big-endian
    write send_str
  end

  # Not expected to be overridden; subclasses should override on_record
  def on_read(data)
    #puts "Received #{data.size} bytes"
    @network_buffer << data

    until @network_buffer.empty?
      avail = @network_buffer.size
      if avail < 4
        puts "Only #{avail} bytes in buffer, header incomplete"
        return nil
      end
      len = @network_buffer[0...4].unpack("N").first
      if avail < (4 + len)
        puts "Only #{avail} bytes in buffer, record incomplete"
        return nil
      end

      #puts "Consuming header plus #{len} bytes"
      bytes = @network_buffer.slice!(0...(4 + len))
      json = JSON.parse(bytes[4..-1])
      #puts "Got: #{json.inspect}"
      on_record json
    end
  end

  def [](*args)
    @last_record[*args]
  end
end
