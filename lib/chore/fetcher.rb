module Chore
  class Fetcher
    attr_reader :manager, :consumers

    def initialize(manager)
      @stopping = false
      @manager = manager
      @strategy = Chore.config.fetcher_strategy.new(self)
    end

    def start
      Chore.logger.info "Fetcher starting up"
      @strategy.fetch
    end

    def stop!
      unless @stopping
        Chore.logger.info "Fetcher shutting down"
        @stopping = true
        @strategy.stop!
      end
    end

    def stopping?
      @stopping
    end
  end
end
