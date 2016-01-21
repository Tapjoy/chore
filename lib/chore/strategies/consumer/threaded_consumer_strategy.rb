require 'chore/strategies/consumer/batcher'
module Chore
  module Strategy
    class ThreadedConsumerStrategy #:nodoc
      attr_accessor :batcher

      Chore::CLI.register_option 'batch_size', '--batch-size SIZE', Integer, 'Number of items to collect for a single worker to process'
      Chore::CLI.register_option 'batch_timeout', '--batch-timeout TIMEOUT', Integer, 'Maximum amount of time in seconds to spend collecting items in a batch, if the batch_size is not reached'
      Chore::CLI.register_option 'threads_per_queue', '--threads-per-queue NUM_THREADS', Integer, 'Number of threads to create for each named queue'

      def initialize(fetcher)
        @fetcher = fetcher
        @batcher = Batcher.new(Chore.config.batch_size)
        @batcher.callback = lambda { |batch| @fetcher.manager.assign(batch) }
        @batcher.schedule(Chore.config.batch_timeout)
        @running = true
      end

      # Begins fetching from queues by spinning up the configured +:threads_per_queue:+ count of threads
      # for each queue you're consuming from.
      # Once all threads are spun up and running, the threads are then joined.
      def fetch
        Chore.logger.debug "Starting up consumer strategy: #{self.class.name}"
        threads = []
        Chore.config.queues.each do |queue|
          Chore.config.threads_per_queue.times do 
            if running?
              threads << start_consumer_thread(queue)
            end
          end
        end

        threads.each(&:join)
      end
      
      # If the ThreadedConsumerStrategy is currently running <tt>stop!</tt> will begin signalling it to stop
      # It will stop the batcher from forking more work, as well as set a flag which will disable it's own consuming
      # threads once they finish with their current work.
      def stop!
        if running?
          Chore.logger.info "Shutting down fetcher: #{self.class.name.to_s}"
          @batcher.stop
          @running = false
        end
      end

      # Returns whether or not the ThreadedConsumerStrategy is running or not
      def running?
        @running
      end

      private 
      # Starts a consumer thread for polling the given +queue+.
      # If <tt>stop!<tt> is called, the threads will shut themsevles down.
      def start_consumer_thread(queue)
        t = Thread.new(queue) do |tQueue|
          begin
            consumer = Chore.config.consumer.new(tQueue)
            consumer.consume do |id, queue_name, queue_timeout, body, previous_attempts|
              # Quick hack to force this thread to end it's work
              # if we're shutting down. Could be delayed due to the
              # weird sometimes-blocking nature of SQS.
              consumer.stop if !running?
              Chore.logger.debug { "Got message: #{id}"}

              work = UnitOfWork.new(id, queue_name, queue_timeout, body, previous_attempts, consumer)
              @batcher.add(work)
            end
          rescue Chore::TerribleMistake
            Chore.logger.error "I've made a terrible mistake... shutting down Chore"
            self.stop!
            @fetcher.manager.shutdown!
          rescue => e
            Chore.logger.error "ThreadedConsumerStrategy#consumer thread raised an exception: #{e.inspect} at #{e.backtrace}"
          end
        end
        t
      end

    end #ThreadedConsumerStrategy
  end
end #Chore
