module Chore
  class SingleConsumerStrategy
    def initialize(fetcher, opts={})
      @fetcher = fetcher
    end

    def fetch
      @fetcher.consumers.first.consume do |id,body|
        work = UnitOfWork.new(id, body, @fetcher.consumers.first)
        @fetcher.manager.assign(work)
      end
    end
  end
end
