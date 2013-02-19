module Chore
  class SingleConsumerStrategy
    def initialize(fetcher, opts={})
      @fetcher = fetcher
    end

    def fetch
      @fetcher.consumers.first.consume do |msg|
        work = UnitOfWork.new(msg.id, msg.body, @fetcher.consumers.first)
        @fetcher.manager.assign(work)
      end
    end
  end

  class Fetcher
    attr_reader :config, :manager, :consumers
    DEFAULT_OPTIONS = {:strategy => SingleConsumerStrategy, :consumers => [{ :class => SQSConsumer, :queue => "tanner_test_queue"}] }
    
    def initialize(manager, opts={})
      @manager = manager
      @config = DEFAULT_OPTIONS.merge(opts)
      @consumers = self.config[:consumers].map {|c| c[:class].new(c[:queue]) }
      @strategy = self.config[:strategy].new(self)
    end

    def start
      @strategy.fetch
    end
  end
end
