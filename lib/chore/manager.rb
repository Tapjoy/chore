module Chore
  class Manager
    attr_reader :config
    WORKERS = {}
    DEFAULT_OPTIONS = {:num_workers => 8}

    def initialize(opts={})
      self.config = DEFAULT_OPTIONS.merge(opts)
    end

    def start
    end

    def spawn_worker
    end
  end
end
