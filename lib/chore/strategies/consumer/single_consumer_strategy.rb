module Chore
  module Strategy
    module Consumer
      class Single
        def initialize(fetcher, opts={})
          @fetcher = fetcher
        end

        def fetch
          Chore.logger.debug "Starting up consumer strategy: #{self.class.name}"
          queues = Chore.config.queues
          raise "When using SingleConsumerStrategy only one queue can be defined. Queues: #{queues}" unless queues.size == 1
          
          @consumer = Chore.config.consumer.new(queues.first)
          @consumer.consume do |id,body|
            work = UnitOfWork.new(id, body, @consumer)
            @fetcher.manager.assign(work)
          end
        end

        def stop!
          Chore.logger.info "Shutting down fetcher: #{self.class.name.to_s}"
          @consumer.stop
        end
      end
    end
  end
end
