require 'chore/strategies/worker/single_worker_strategy'

module Chore
  module Strategy
    class SingleBatchedWorkerStrategy < SingleWorkerStrategy
      def assign(work)
        if workers_available?
          @worker = BatchedWorker.new(work, @options)
          @worker.start
          @worker = nil
          true
        end
      end
    end
  end
end
