module Chore
  class ThreadPerConsumerStrategy
    attr_reader :batch

    def initialize(fetcher)
      @fetcher = fetcher
      @batch = []
    end

    def fetch
      threads = []
      mutex = Mutex.new
      Chore.config.queues.each do |queue|
        threads << Thread.new(queue) do |tQueue|
          consumer = Chore.config.consumer.new(tQueue)
          consumer.consume do |id, body|
            work = UnitOfWork.new(id, body, consumer)
            mutex.synchronize do
              if @batch.size < Chore.config.batch_size
                @batch << work
              else
                @fetcher.manager.assign(@batch)
                @batch.clear
              end
            end
          end
        end
      end

      threads.each(&:join)
    end
  end
end
