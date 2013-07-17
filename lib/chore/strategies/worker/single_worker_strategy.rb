module Chore
  module Strategy
    class SingleWorkerStrategy
      def initialize(manager)
        @manager = manager
        @worker = nil
      end

      def start;end
      def stop!;end

      def assign(work)
        if workers_available?
          @worker = Worker.start(work)
          true
        end
      end

      def workers_available?
        @worker.nil?
      end
    end
  end
end
