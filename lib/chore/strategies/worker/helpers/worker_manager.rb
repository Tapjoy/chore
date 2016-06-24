require 'chore/strategies/worker/helpers/ipc'

module Chore
  module Strategy
    class WorkerManager #:nodoc:
      include Ipc

      def initialize(master_socket)
        @master_socket = master_socket
        @num_connection_failures = 0
        @pid_to_worker = {}
        @socket_to_worker = {}
      end

      # Create num of missing workers and sockets and attach them for the
      # master
      def create_and_attach_workers
        create_sockets do |sockets|
          attach_workers(sockets)
        end
      end

      # Reap dead workers and create new ones to replace them
      def respawn_terminated_workers!
        Chore.logger.info 'WM: Respawning terminated workers'
        reap_workers
        create_and_attach_workers
      end

      # Stop children with the given kill signal and wait for them to die
      def stop_workers(sig)
        begin
          Chore.logger.info { "WM: Sending #{sig} to workers" }
          Process.kill(sig, 0)
        rescue Errno::ESRCH => e
          Chore.logger.error "WM: Signal to children error: #{e}"
        end
        # TODO: Sleep for the shutdown timeout and kill any remaining workers
        reap_workers
      end

      # Return all the worker sockets
      def worker_sockets
        @socket_to_worker.keys
      end

      # Return the workers associated with a given array of sockets.
      # +block+:: A block can be provided to perform tasks on the workers
      # associated with the sockets given
      def ready_workers(sockets = [], &block)
        workers = @socket_to_worker.values_at(*sockets)
        yield workers if block_given?
        workers
      end

      private

      def create_sockets(&block)
        num_new_sockets = Chore.config.num_workers - @pid_to_worker.size
        new_sockets = []

        num_new_sockets.times do
          new_sockets << add_worker_socket
        end

        yield new_sockets if block_given?
        new_sockets
      end

      def create_workers(num)
        num.times do
          pid = fork do
            run_worker_instance
          end

          Chore.logger.info "WM: created_worker #{pid}"
          # Keep track of the new worker process
          @pid_to_worker[pid] = WorkerInfo.new(pid)
        end

        raise 'WM: Not enough workers' if inconsistent_worker_number
        Chore.logger.info "WM: created #{num} new workers"
      end

      def attach_workers(sockets)
        create_workers(sockets.size)

        sockets.each do |socket|
          begin
            readable, _, _ = select_sockets(socket, nil, 2)

            if readable.nil?
              socket.close
              @num_connection_failures += 1
              next
            end

            r_socket = readable.first
            reported_pid = read_msg(r_socket)

            assigned_worker = @pid_to_worker[reported_pid]
            assigned_worker.socket = socket
            @socket_to_worker[socket] = assigned_worker
            @num_connection_failures = 0

            Chore.logger.info "WM: Connected #{reported_pid} with #{r_socket}"
          rescue Errno::ECONNRESET
            Chore.logger.info "WM: A worker failed to connect to #{socket}"
            socket.close
            @num_connection_failures += 1
            next
          end
        end

        check_connection_failures
        kill_unattached_workers
        Chore.logger.info 'WM: Finished attaching workers'
      end

      def check_connection_failures
        if @num_connection_failures >= Chore.config.num_workers * 2
          Chore.logger.info "WM: #{@num_connection_failures} failed connections, exiting chore"
          exit(false)
        end
      end

      # Check that number of workers registered in master match the config
      def inconsistent_worker_number
        Chore.config.num_workers != @pid_to_worker.size
      end

      # Initialize and start a new worker instance
      def run_worker_instance
        PreforkedWorker.new.start_worker(@master_socket)
      ensure
        exit!(true)
      end

      # Kill workers that failed to connect to the master
      def kill_unattached_workers
        @pid_to_worker.each do |pid, worker|
          next unless worker.socket.nil?
          Process.kill('KILL', pid)
        end
      end

      # Wait for terminated workers to die and remove their references from
      # master
      def reap_workers
        dead_workers = @pid_to_worker.select do |pid, worker|
          reap_process(pid)
        end

        dead_workers.each do |pid, worker|
          dead_worker = @pid_to_worker.delete(pid)
          @socket_to_worker.delete(dead_worker.socket)
          Chore.logger.info "WM: Removed preforked worker:#{worker.pid} - #{worker.socket}"
        end
      end

      # Non-blocking wait for process to die. Returns whether it stopped
      def reap_process(pid)
        status = Process.wait(pid, Process::WNOHANG)
        case status
        when nil # Process is still running
          return false
        when pid # Collected status of this pid
          return true
        end
      rescue Errno::ECHILD
        # Child process has already terminated
        true
      end

      def fork(&block)
        Kernel.fork(&block)
      end
    end
  end
end
