require 'chore/signal'
require 'socket'
require 'timeout'
require 'chore/strategies/worker/helpers/ipc'

module Chore
  module Strategy
    class PreforkedWorker #:nodoc:
      include Util
      include Ipc

      NUM_TO_SIGNAL = {'2' => :INT, '3' => :QUIT, '4' => :TERM}.freeze

      def initialize(_opts = {})
        @manager_pid = Process.ppid
        @consumer_cache = {}
        @running = true
        post_fork_setup
      end

      def start_worker(master_socket)
        Chore.logger.info 'PFW: Worker starting'
        raise 'PFW: Did not get master_socket' unless master_socket
        connection = connect_to_master(master_socket)
        worker(connection)
      rescue => e
        Chore.logger.error "PFW: Shutting down #{e.message} #{e.backtrace}"
      end

      private

      def worker(connection)
        while running?
          # Select on the connection to the master and the self pipe
          readables, _, _ex = select_sockets(connection,nil, Chore.config.shutdown_timeout)

          if readables.nil? # timeout
            Chore.logger.info "PFW: Shutting down due to timeout"
            break
          end

          # Get the work from the connection to master
          work = read_msg(connection)

          # When the Master (manager process) dies, the sockets are set to
          # readable, but there is no data in the socket. In this case we check
          # to see if the manager is actually dead, and in that case, we exit.
          if work.nil? && is_orphan?
            Chore.logger.info "PFW: Manager no longer alive; Shutting down"
            break
          end

          unless work.nil?
            # Do the work
            process_work(work)
            # Alert master that worker is ready to receive more work
            signal_ready(connection)
          end
        end
        Chore.logger.debug "PFW: Master process terminating"
        exit(true)
      end

      # Method wrapper around @running makes it easier to write specs
      def running?
        @running
      end

      # Connects to the master socket, sends its PID, send a ready for work
      # message, and returns the connection
      def connect_to_master(master_socket)
        Chore.logger.info 'PFW: connect protocol started'
        child_connection(master_socket).tap do |conn|
          send_msg(conn, Process.pid)
          signal_ready(conn)
          Chore.logger.info 'PFW: connect protocol completed'
        end
      end

      def post_fork_setup
        # Immediately swap out the process name so that it doesn't look like
        # the master process
        procline("chore-worker-#{Chore::VERSION}:Started:#{Time.now}")

        # We need to reset the logger after fork. This fixes a longstanding bug
        # where workers would hang around and never die
        Chore.logger = nil

        config = Chore.config
        # When we fork, the consumer's/publisher's need their connections reset.
        # The specifics of this are queue dependent, and may result in a noop.
        config.consumer.reset_connection!
        # It is possible for this to be nil due to configuration woes with chore
        config.publisher.reset_connection! if Chore.config.publisher

        trap_signals(NUM_TO_SIGNAL)
      end

      def process_work(work)
        work = [work] unless work.is_a?(Array)
        work.each do |item|
          item.consumer = consumer(item.queue_name)
          begin
            Timeout.timeout( item.queue_timeout ) do
              worker = Worker.new(item)
              worker.start
            end
          rescue Timeout::Error => ex
            Chore.logger.info "PFW: Worker #{Process.pid} timed out"
            Chore.logger.info "PFW: Worker time out set at #{item.queue_timeout} seconds"
            exit(true)
          end
        end
      end

      # We need to resue Consumer objects because it takes 500ms to recreate
      # each one.
      def consumer(queue)
        unless @consumer_cache.key?(queue)
          raise Chore::TerribleMistake if @consumer_cache.size >= Chore.config.queues.size
          @consumer_cache[queue] = Chore.config.consumer.new(queue)
        end
        @consumer_cache[queue]
      end

      # In the event of a trapped signal, write to the self-pipe
      def trap_signals(signal_hash)
        Signal.reset

        signal_hash.each do |sig_num, signal|
          Signal.trap(signal) do
            Chore.logger.debug "PFW: received signal: #{signal}"
            @running = false
            sleep(Chore.config.shutdown_timeout)
            Chore.logger.debug "PFW: Worker process terminating"
            exit(true)
          end
        end
      end

      def is_orphan?
        Process.ppid != @manager_pid
      end
    end
  end
end
