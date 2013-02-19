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
end
