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
          @worker = Worker.new(work)
          @worker.start
          @worker = nil
          true
        end
      end

      def workers_available?
        @worker.nil?
      end
    end
  end
end
