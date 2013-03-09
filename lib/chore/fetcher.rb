module Chore
  class Fetcher
    attr_reader :manager, :consumers

    def initialize(manager)
      @stopping = false
      @manager = manager
      @consumers = Chore.config.queues.map {|q| Chore.config.consumer.new(q) }
      @strategy = Chore.config.fetcher_strategy.new(self)
    end

    def start
      @strategy.fetch
    end

    def self.stop!
      Chore.logger.info "Fetcher shutting down"
      @consumers.each(&:stop)
      @stopping = true
    end

    def self.stopping?
      @stopping
    end
  end
end
