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
    attr_reader :manager, :consumers
    
    def initialize(manager)
      @manager = manager
      @consumers = Chore.config.queues.map {|q| Chore.config.consumer.new(q) }
      @strategy = Chore.config.fetcher_strategy.new(self)
    end

    def start
      @strategy.fetch
    end
  end
end
