module Chore

  class SingleWorkerStrategy 
    def initialize(manager)
      @manager = manager
      @worker = nil
    end

    def assign(work)
      if workers_available?
        @worker = Worker.new
        @worker.start(work)
        @worker = nil
        true
      end
    end

    private
    def workers_available?
      @worker.nil?
    end
  end

  class Manager
    WORKERS = {}

    def initialize()
      @worker_strategy = Chore.config.worker_strategy.new(self)
      @fetcher = Chore.config.fetcher.new(self)
    end

    def start
      @fetcher.start
    end

    def assign(work)
      until @assigned 
        @assigned = @worker_strategy.assign(work)
        sleep(0.2)
      end
    end

    def spawn_worker
    end
  end
end
