module Chore
  module Strategy

    # Consumer strategy for requesting batches of work in a linear fashion. Ideally used for running
    # a single Chore job locally in a development environment where performance or throughput may not matter.
    # <tt>SingleConsumerStrategy</tt> will raise an exception if you're configured to listen for more than 1 queue
    class SingleConsumerStrategy
      def initialize(fetcher, opts={})
        @fetcher = fetcher
      end

      # Begins fetching from the configured queue by way of the configured Consumer. This can only be used if you have a
      # single queue which can be kept up with at a relatively low volume. If you have more than a single queue
      # configured, it will raise an exception.
      #
      # @return [TrueClass, FalseClass]
      def fetch
        Chore.logger.debug "Starting up consumer strategy: #{self.class.name}"
        queues = Chore.config.queues
        raise "When using SingleConsumerStrategy only one queue can be defined. Queues: #{queues}" unless queues.size == 1

        @consumer = Chore.config.consumer.new(queues.first)
        @consumer.consume do |id,queue_name,queue_timeout,body,previous_attempts|
          work = UnitOfWork.new(id, queue_name, queue_timeout, body, previous_attempts, @consumer)
          @fetcher.manager.assign(work)
        end
      end

      # Stops consuming messages from the queue
      def stop!
        Chore.logger.info "Shutting down fetcher: #{self.class.name.to_s}"
        @consumer.stop
      end
    end
  end
end
