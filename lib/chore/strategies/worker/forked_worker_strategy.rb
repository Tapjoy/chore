module Chore
  module Strategy
    class ForkedWorkerStrategy
      attr_accessor :workers

      def initialize(manager)
        @manager = manager
        @workers = {}

        trap_master_signals

        Chore.run_hooks_for(:before_first_fork)
      end

      # Start up the worker strategy. In this particular case, what we're doing
      # is starting up a WorkerListener, so we can talk to the children.
      def start
        Chore.logger.debug "Starting up worker strategy: #{self.class.name}"
      end

      # Stop the workers. The particulars of the implementation here are that we
      # send a QUIT signal to each child, wait one minute for it to finish the last job
      # it was working on. If it times out, then we send KILL. In an ideal world this means
      # that <tt>stop!</tt> is non-destructive in that it allow each worker to complete it's
      # current job before dying.
      def stop!
        Chore.logger.info { "Manager #{Process.pid} stopping" }
        begin
          signal_children("QUIT")
          Timeout::timeout(60) do
            Process.waitall
          end
        rescue Timeout::Error
          Chore.logger.error "Timed out waiting for children to terminate. Terminating with prejudice."
          signal_children("KILL")
        end
      end

      # Take a UnitOfWork (or an Array of UnitOfWork) and assign it to a Worker. We only
      # assign work if there are <tt>workers_available?</tt>.
      def assign(work)
        if workers_available?
          w = Worker.new(work)
          Chore.run_hooks_for(:before_fork,w)
          pid = fork do
            after_fork(w)

            Chore.run_hooks_for(:after_fork,w)
            procline("Started:#{Time.now}")
            begin
              w.start
              Chore.logger.info("Finished:#{Time.now}")
            ensure
              Chore.run_hooks_for(:before_fork_shutdown)
            end
          end
          Chore.logger.debug { "Forked worker #{pid}"}
          workers[pid] = w
        end
      end

      
      def workers_available?
        workers.length < Chore.config.num_workers
      end

      private

      def trap_master_signals
        trap('CHLD') { reap_terminated_workers! }
      end

      def trap_child_signals(worker)
        # Register a new QUIT handler to make the current worker
        # finish this job, and not complete another one.
        trap("INT") { worker.stop! }
        trap("QUIT") { worker.stop! }
      end

      def clear_child_signals
        # Remove handlers from the parent process
        trap "INT",  "DEFAULT"
        trap "CHLD", "DEFAULT"
      end


      # Only call this in the forked child. It resets some things that need fixing up
      # in the child.
      def after_fork(worker)
        clear_child_signals
        trap_child_signals(worker)

        # We need to reset the logger after fork. This fixes a longstanding bug
        # where workers would hang around and never die
        Chore.logger = Logger.new(STDOUT)
        
        # When we fork, the consumer's need their connections reset. The specifics of this
        # are queue dependent, and may result in a noop.
        Chore.config.consumer.reset_connection!
      end

      def reap_terminated_workers!
        # Avoid a SIGCHLD race condition by reaping all available child processes
        while pid = Process.wait(-1, Process::WNOHANG)
          workers.delete(pid)
          Chore.logger.debug { "Removed finished worker #{pid}"}
        end
      rescue Errno::ECHILD
        # Child processes have already terminated
      end

      # Wrapper around fork for specs.
      def fork(&block)
        Kernel.fork(&block)
      end

      def procline(str)
        Chore.logger.info str
        $0 = "chore-#{Chore::VERSION}:#{str}"
      end

      def signal_children(sig)
        @workers.keys.each do |pid|
          begin
            Chore.logger.info { "Sending #{sig} to: #{pid}" }
            Process.kill(sig, pid)
          rescue Errno::ESRCH
          end
        end
      end

    end
  end
end
