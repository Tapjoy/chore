module Chore
  module Strategy
    
    # Worker strategy for performing batches of work in a linear fashion. Ideally used for running
    # Chore jobs locally in a development environment where performance or throughput may not matter.
    class SingleWorkerStrategy

      attr_reader :worker

      def initialize(manager)
        @manager = manager
        @worker = nil
      end

      # Starts the <tt>SingleWorkerStrategy</tt>. Currently a noop
      def start;end

      # Stops the <tt>SingleWorkerStrategy</tt> if there is a worker to stop
      def stop!
        worker.stop! if worker
      end

      # Assigns work if there isn't already a worker in progress. Otherwise, is a noop
      def assign(work)
        if workers_available?
          @worker = Worker.new(work)
          @worker.start
          @worker = nil
          true
        end
      end

      # Returns true if there is currently no worker
      def workers_available?
        @worker.nil?
      end
    end
  end
end
