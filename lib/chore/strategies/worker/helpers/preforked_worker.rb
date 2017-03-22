require 'chore/signal'
require 'socket'
require 'timeout'
require 'chore/strategies/worker/helpers/ipc'

module Chore
  module Strategy
    class PreforkedWorker #:nodoc:
      include Util
      include Ipc

      def initialize(_opts = {})
        Chore.logger.info "PFW: #{Process.pid} initializing"
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
        raise e
      end

      private

      def worker(connection)
        worker_killer = WorkerKiller.new
        while running?
          # Select on the connection to the master and the self pipe
          readables, _, ex = select_sockets(connection, nil, Chore.config.shutdown_timeout)

          if readables.nil? # timeout
            next
          end

          read_socket = readables.first

          # Get the work from the connection to master
          work = read_msg(read_socket)

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

            worker_killer.check_requests
            worker_killer.check_memory

            # Alert master that worker is ready to receive more work
            signal_ready(read_socket)
          end
        end
      rescue Errno::ECONNRESET, Errno::EPIPE
        Chore.logger.info "PFW: Worker-#{Process.pid} lost connection to master, shutting down"
      ensure
        Chore.logger.info "PFW: Worker process terminating"
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

        # Ensure that all signals are handled before we hand off a hook to the
        # application.
        trap_signals

        Chore.run_hooks_for(:after_fork,self)
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
            raise ex
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

      def trap_signals
        Signal.reset

        [:INT, :QUIT, :TERM].each do |signal|
          Signal.trap(signal) do
            Chore.logger.info "PFW: received signal: #{signal}"
            @running = false
            sleep(Chore.config.shutdown_timeout)
            Chore.logger.info "PFW: Worker process terminating"
            exit(true)
          end
        end

        Signal.trap(:USR1) do
          Chore.reopen_logs
          Chore.logger.info "PFW: Worker process reopened log"
        end
      end

      def is_orphan?
        Process.ppid != @manager_pid
      end
    end
  end
end
