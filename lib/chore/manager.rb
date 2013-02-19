module Chore
  class ForkingWorkerStrategy
    def initialize(manager)
    end
  end

  class Manager
    attr_reader :config
    WORKERS = {}
    DEFAULT_OPTIONS = {:num_workers => 8, :worker_strategy => ForkingWorkerStrategy, :fetcher => Fetcher }

    def initialize(opts={})
      @config = DEFAULT_OPTIONS.merge(opts)
      @worker_strategy = self.config[:worker_strategy].new(self)
      #@fetcher = self.config[:fetcher].new(self)
    end

    def start
      # Start up fetcher
      # Begin doing whatever the worker strategy wants to do?
    end

    def assign(msg)
    end

    def spawn_worker
    end
  end
end
