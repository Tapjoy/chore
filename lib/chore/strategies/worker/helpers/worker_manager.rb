require 'chore/strategies/worker/helpers/ipc'

module Chore
  module Strategy
    class WorkerManager #:nodoc:
      include Ipc

      def initialize(master_socket)
        @master_socket = master_socket
        @pid_to_worker = {}
        @socket_to_worker = {}
      end

      # Create num of missing workers and sockets and attach them for the
      # master
      def create_and_attach_workers
        create_workers do |num_workers|
          attach_workers(num_workers)
        end
      end

      # Reap dead workers and create new ones to replace them
      def respawn_terminated_workers!
        Chore.logger.debug 'WM: Respawning terminated workers'
        reap_workers
        create_and_attach_workers
      end

      # Stop children with the given kill signal and wait for them to die
      def stop_workers(sig)
        @pid_to_worker.each do |pid, worker|
          begin
            Chore.logger.info { "WM: Sending #{sig} to: #{pid}" }
            Process.kill(sig, pid)
          rescue Errno::ESRCH => e
            Chore.logger.error "WM: Signal to children error: #{e}"
          end
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

      # Creates worker processes until we have the number of workers defined
      # by the configuration. Initializes and starts a worker instance in each
      # of the new processes.
      # +block+:: Block can be provided to run tasks on the number of newly
      # created worker processes.
      def create_workers(&block)
        num_created_workers = 0

        while @pid_to_worker.size < Chore.config.num_workers
          pid = fork do
            run_worker_instance
          end

          Chore.logger.info "WM: created_worker #{pid}"
          # Keep track of the new worker process
          @pid_to_worker[pid] = WorkerInfo.new(pid)
          num_created_workers += 1
        end

        raise 'WM: Not enough workers' if inconsistent_worker_number
        Chore.logger.info "WM: created #{num_created_workers} workers"
        yield num_created_workers if block_given?
        num_created_workers
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

      # Creates individual sockets for each worker to use and attaches them to
      # the correct worker
      def attach_workers(num)
        Chore.logger.info "WM: Started attaching #{num} workers"

        create_worker_sockets(num).each do |socket|
          reported_pid = read_from_worker(socket)
          Chore.logger.debug "WM: Connected #{reported_pid} with #{socket}"

          next if reported_pid.nil?

          assigned_worker = @pid_to_worker[reported_pid]
          assigned_worker.socket = socket

          @socket_to_worker[socket] = assigned_worker
        end

        # If the connection from a worker times out, we are unable to associate
        # the process with a connection and so we kill the worker process
        kill_unattached_workers
        Chore.logger.info 'WM: Finished attaching workers'
      end

      # Create num amount of sockets that are available for worker connections
      def create_worker_sockets(num)
        Array.new(num) do
          add_worker_socket
        end
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
          Chore.logger.debug "WM: Removed preforked worker:#{worker.pid} - #{worker.socket}"
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
