module Chore
  module Strategy
    
    # Worker strategy for performing batches of work in a linear fashion. Ideally used for running
    # Chore jobs locally in a development environment where performance or throughput may not matter.
    class SingleWorkerStrategy

      attr_reader :worker

      def initialize(manager, opts={})
        @options = opts
        @manager = manager
        @worker = nil
      end

      # Starts the <tt>SingleWorkerStrategy</tt>. Currently a noop
      def start;end

      # Stops the <tt>SingleWorkerStrategy</tt> if there is a worker to stop
      def stop!
        worker.stop! if worker
      end

      # Assigns work if there isn't already a worker in progress. In this, the
      # single worker strategy, this should never be called if the worker is in
      # progress.
      def assign(work)
        if workers_available?
          begin
            @worker = worker_klass.new(work, @options)
            @worker.start
            true
          ensure
            @worker = nil
          end
        else
          Chore.logger.error { "#{self.class}#assign: single worker is unavailable, but assign has been re-entered: #{caller * "\n"}" }
        end
      end

      def worker_klass
        Worker
      end

      # Returns true if there is currently no worker
      def workers_available?
        @worker.nil?
      end
    end
  end
end
