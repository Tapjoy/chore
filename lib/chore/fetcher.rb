module Chore
  class BasicFetchingStrategy
    def initialize(fetcher, opts={})
      @fetcher = fetcher
    end

    def fetch
      @fetcher.consumer.consume do |msg|
        @fetcher.manager.assign(msg)
      end
    end
  end

  class Fetcher
    attr_reader :config, :manager, :consumer
    DEFAULT_OPTIONS = {:num_consumers => 1, :strategy => BasicFetchingStrategy, :consumer => SQSConsumer }
    
    def initialize(manager, opts={})
      @manager = manager
      @config = DEFAULT_OPTIONS.merge(opts)
      @consumer = self.config[:consumer].new(self.config[:queue_name])
      @strategy = self.config[:strategy].new(self)
    end

    def start
      @strategy.fetch
    end
  end
end
