module Chore
  class BasicFetchingStrategy
    def initialize(fetcher)
    end
  end

  class Fetcher
    attr_reader :config
    DEFAULT_OPTIONS = {:num_consumers => 1, :fetching_strategy => BasicFetchingStrategy, :consumer => SQSConsumer }
    
    def initialize(manager, opts={})
      @manager = manager
      @config = DEFAULT_OPTIONS.merge(opts)
      @consumer = self.config[:consumer].new(self.config[:queue_name])
    end

    def fetch
      @consumer.consume do |msg|
        @manager.assign(msg)
      end
    end 
  end
end
