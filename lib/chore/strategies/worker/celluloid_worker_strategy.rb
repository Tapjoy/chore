require 'celluloid'
module Chore
  module Strategy
    class CelluloidWorker < Worker
      include Celluloid

      def start_with_work(work=[])
        @work = *work
        start
      end
    end

    class CelluloidWorkerStrategy

      attr_reader :worker

      def initialize(manager)
        @manager = manager
        @supervisor = nil
        @pool = nil
      end

      def start
        @supervisor = Celluloid::SupervisionGroup.run!
        @pool = @supervisor.pool(CelluloidWorker, as: :workers).actor
      end

      def stop!
        @supervisor.terminate if @supervisor
      end

      def assign(work)
        if workers_available?
          Celluloid::Actor[:workers].async.start_with_work(work)
          true
        end
      end

      def workers_available?
        @pool.idle_size > 0
      end
    end
  end
end
