require 'chore/signal'

module Chore
  module Strategy
    class ForkedWorkerStrategy
      attr_accessor :workers

      def initialize(manager)
        @manager = manager
        @stopped = false
        @workers = {}
        @queue = Queue.new
        Chore.config.num_workers.times { @queue << :worker }

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
        @stopped = true
        Chore.logger.info { "Manager #{Process.pid} stopping" }

        # Instead of using Process.waitall (which is a blocking operation that can
        # cause the master process to hang), use a Unicorn style non-blocking
        # shutdown process.
        limit = Time.now + Chore.config.shutdown_timeout
        until workers.empty? || Time.now > limit
          signal_children("QUIT")
          sleep(0.1)
          reap_terminated_workers!
        end

        if !workers.empty?
          Chore.logger.error "Timed out waiting for children to terminate. Terminating with prejudice."
          signal_children("KILL")
        end
      end

      # Take a UnitOfWork (or an Array of UnitOfWork) and assign it to a Worker. We only
      # assign work if there are <tt>workers_available?</tt>.
      def assign(work)
        return unless acquire_worker

        begin
          w = Worker.new(work)
          Chore.run_hooks_for(:before_fork,w)
          pid = nil
          Chore.run_hooks_for(:around_fork,w) do
            pid = fork do
              after_fork(w)
              Chore.run_hooks_for(:within_fork,w) do

                Chore.run_hooks_for(:after_fork,w)
                procline("Started:#{Time.now}")
                begin
                  Chore.logger.info("Started worker:#{Time.now}")
                  w.start
                  Chore.logger.info("Finished worker:#{Time.now}")
                ensure
                  Chore.run_hooks_for(:before_fork_shutdown)
                  exit!(true)
                end
              end #within_fork
            end #around_fork
          end

          Chore.logger.debug { "Forked worker #{pid}"}
          workers[pid] = w
        rescue => ex
          Chore.logger.error { "Failed to fork worker: #{ex.message} #{ex.backtrace * "\n"}"}
          release_worker
        end
      end

      private

      def trap_master_signals
        Signal.trap('CHLD') { reap_terminated_workers! }
      end

      def trap_child_signals(worker)
        # Register a new QUIT handler to make the current worker
        # finish this job, and not complete another one.
        Signal.trap("INT") { worker.stop! }
        Signal.trap("QUIT") { worker.stop! }
        #By design, we do nothing in children on USR1, so we are not re-defining this like we do INT and QUIT
      end

      def clear_child_signals
        # Remove handlers from the parent process
        Signal.reset
      end

      # Attempts to essentially acquire a lock on a worker.  If no workers are
      # available, then this will block until one is.
      def acquire_worker
        result = @queue.pop

        if @stopped
          # Strategy has stopped since the worker was acquired.  If workers are
          # allowed to run even though the strategy is stopped, this could result
          # in forks occuring while the CLI is calling +Kernel#exit+ -- which can
          # cause chore to hang.
          release_worker
          nil
        else
          result
        end
      end

      # Releases the lock on a worker so that another thread can pick it up.
      def release_worker
        @queue << :worker
      end

      # Only call this in the forked child. It resets some things that need fixing up
      # in the child.
      def after_fork(worker)
        clear_child_signals
        trap_child_signals(worker)

        # We need to reset the logger after fork. This fixes a longstanding bug
        # where workers would hang around and never die
        Chore.logger = nil

        # When we fork, the consumer's / publisher's need their connections reset. The specifics of this
        # are queue dependent, and may result in a noop.
        Chore.config.consumer.reset_connection!
        Chore.config.publisher.reset_connection! if Chore.config.publisher #It is possible for this to be nil due to configuration woes with chore
      end

      # Reaps any in-flight workers that have completed.  This only relies on
      # known process ids instead of discovering all child processes from the
      # OS.  By doing this, we avoid running into a tight loop reaping
      # short-lived forks.
      def reap_terminated_workers!
        # Take a snapshot in time of what workers are in flight
        pids = workers.keys

        pids.each do |pid|
          reaped = false
          begin
            reaped = Process.wait(pid, Process::WNOHANG)
          rescue Errno::ECHILD => ex
            # Child process has already terminated
            reaped = true
          end

          # Clean up / release worker
          if reaped && workers.delete(pid)
            release_worker
            Chore.logger.debug { "Removed finished worker #{pid}"}
          end
        end
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
