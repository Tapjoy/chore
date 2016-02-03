require 'socket'

module Chore
  module Strategy
    module Ipc #:nodoc:

      #TODO do we need this as a optional param
      UNIX_SOCKET = './prefork_worker_sock'.freeze

      def create_master_socket
        File.delete UNIX_SOCKET if File.exist? UNIX_SOCKET
        UNIXServer.new(UNIX_SOCKET).tap do | socket |
          socket.setsockopt(:SOCKET, :REUSEADDR, true)
        end
      end

      def child_connection(socket)
        socket.accept
      end

      # Sending a message to a socket (must be a connected socket)
      def send_msg(socket, msg)
        raise "send_msg cannot send empty messages" if msg.nil? || msg.size == 0
        message = Marshal.dump(msg)
        encoded_size = [message.size].pack('L>')
        encoded_message = "#{encoded_size}#{message}"
        socket.send encoded_message, 0
      end

      # read a message from socket (must be a connected socket)
      def read_msg(socket)
        encoded_size = socket.recv(4, Socket::MSG_PEEK)
        return nil if encoded_size.nil? || encoded_size == ""
        size = encoded_size.unpack('L>').first
        encoded_message = socket.recv(4 + size)
        Marshal.load(encoded_message[4..-1])
      end

      # read a message from socket (must be a connected socket)
      def read_from_worker(socket)
        readable, _, _ = IO.select([socket], nil, nil, 2)
        return if readable.nil?
        read_msg(readable[0])
      end

      def add_worker_socket
        UNIXSocket.new(UNIX_SOCKET).tap do | socket |
          socket.setsockopt(:SOCKET, :REUSEADDR, true)
        end
      end

      def clear_ready(socket)
        _ = socket.gets
      end

      def signal_ready(socket)
        socket.puts 'R'
      end

      def select_sockets(sockets, self_pipe = nil, timeout = 0.5)
        all_socks = [ sockets, self_pipe ].flatten.compact
        IO.select(all_socks, nil, nil, timeout)
      end

      # Used for unit tests
      def ipc_help
        :available
      end
    end
  end
end
