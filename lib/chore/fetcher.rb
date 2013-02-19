module Chore
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
