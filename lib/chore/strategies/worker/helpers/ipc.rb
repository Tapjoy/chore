require 'socket'

module Chore
  module Strategy
    module Ipc #:nodoc:
      BIG_ENDIAN = 'L>'.freeze
      MSG_BYTES = 4
      READY_MSG = 'R'

      def create_master_socket
        File.delete socket_file if File.exist? socket_file
        UNIXServer.new(socket_file).tap do |socket|
          socket_options(socket)
        end
      end

      def child_connection(socket)
        socket.accept
      end

      # Sending a message to a socket (must be a connected socket)
      def send_msg(socket, msg)
        raise 'send_msg cannot send empty messages' if msg.nil? || msg.size.zero?
        message = Marshal.dump(msg)
        encoded_size = [message.size].pack(BIG_ENDIAN)
        encoded_message = "#{encoded_size}#{message}"
        socket.send encoded_message, 0
      end

      # read a message from socket (must be a connected socket)
      def read_msg(socket)
        encoded_size = socket.recv(MSG_BYTES, Socket::MSG_PEEK)
        return if encoded_size.nil? || encoded_size == ''

        size = encoded_size.unpack(BIG_ENDIAN).first
        encoded_message = socket.recv(MSG_BYTES + size)
        Marshal.load(encoded_message[MSG_BYTES..-1])
      rescue Errno::ECONNRESET => ex
        Chore.logger.info "IPC: Connection was closed on socket #{socket}"
        raise ex
      end

      def add_worker_socket
        UNIXSocket.new(socket_file).tap do |socket|
          socket_options(socket)
        end
      end

      def clear_ready(socket)
        _ = socket.gets
      end

      def signal_ready(socket)
        socket.puts READY_MSG
      rescue Errno::EPIPE => ex
        Chore.logger.info 'IPC: Connection was shutdown by master'
        raise ex
      end

      def select_sockets(sockets, self_pipe = nil, timeout = 0.5)
        all_socks = [sockets, self_pipe].flatten.compact
        IO.select(all_socks, nil, all_socks, timeout)
      end

      def delete_socket_file
        File.unlink(socket_file)
      rescue
        nil
      end

      # Used for unit tests
      def ipc_help
        :available
      end

      private

      # TODO: Decide if we should make this customizable via an optional param
      def socket_file
        "./prefork_worker_sock-#{Process.pid}"
      end

      def socket_options(socket)
        socket.setsockopt(:SOCKET, :REUSEADDR, true)
      end
    end
  end
end
