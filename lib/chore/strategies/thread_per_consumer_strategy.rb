module Chore
  class ThreadPerConsumerStrategy
    def initialize(fetcher)
      @fetcher = fetcher
    end

    def fetch
      threads = []
      mutex = Mutex.new
      fetcher.config[:queues].each do |queue|
        threads << Thread.new(queue) do |tQueue|
          consumer = fetcher.config[:consumer].new(tQueue)
          consumer.consume do |msg|
            work = UnitOfWork.new(msg.id, msg.body, consumer)
            mutex.synchronize do
              fetcher.manager.assign(work)
            end
          end
        end
      end

      threads.map(&:join)
    end
  end
end
