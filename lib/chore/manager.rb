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
    attr_reader :config
    WORKERS = {}
    DEFAULT_OPTIONS = {:num_workers => 1, :worker_strategy => SingleWorkerStrategy, :fetcher => Fetcher }

    def initialize(opts={})
      @config = DEFAULT_OPTIONS.merge(opts)

      @worker_strategy = self.config[:worker_strategy].new(self)
      #@fetcher = self.config[:fetcher].new(self)
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
