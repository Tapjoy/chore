module Chore
  module Strategy
    
    # Worker strategy for performing batches of work in a linear fashion. Ideally used for running
    # Chore jobs locally in a development environment where performance or throughput may not matter.
    class SingleWorkerStrategy

      attr_reader :worker

      def initialize(manager, opts={})
        @options = opts
        @manager = manager
        @stopped = false
        @worker = nil
        @queue = Queue.new
        @queue << :worker
      end

      # Starts the <tt>SingleWorkerStrategy</tt>. Currently a noop
      def start;end

      # Stops the <tt>SingleWorkerStrategy</tt> if there is a worker to stop
      def stop!
        return if @stopped

        @stopped = true
        Chore.logger.info { "Manager #{Process.pid} stopping" }

        worker.stop! if worker
      end

      # Assigns work if there isn't already a worker in progress. In this, the
      # single worker strategy, this should never be called if the worker is in
      # progress.
      def assign(work)
        return unless acquire_worker

        begin
          @worker = worker_klass.new(work, @options)
          @worker.start
          true
        ensure
          release_worker
        end
      end

      def worker_klass
        Worker
      end

      private

      # Attempts to essentially acquire a lock on a worker.  If no workers are
      # available, then this will block until one is.
      def acquire_worker
        result = @queue.pop

        if @stopped
          # Strategy has stopped since the worker was acquired
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
    end
  end
end
