module Chore
  class SingleWorkerStrategy 
    def initialize(manager)
      @manager = manager
      @worker = nil
    end

    def start;end

    def assign(work)
      if workers_available?
        @worker = Worker.new
        @worker.start(work)
        @worker = nil
        true
      end
    end

    def workers_available?
      @worker.nil?
    end
  end
end
