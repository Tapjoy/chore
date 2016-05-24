module Chore
  module Strategy
    class ThrottledConsumerStrategy #:nodoc:
      def initialize(fetcher)
        @fetcher = fetcher
        @queue = SizedQueue.new(Chore.config.num_workers)
        @max_queue_size = Chore.config.num_workers
        @consumers_per_queue = Chore.config.threads_per_queue
        @running = true
        @consumers = []
      end

      # Begins fetching from queues by spinning up the configured
      # +:threads_per_queue:+ count of threads for each
      # queue you're consuming from.
      # Once all threads are spun up and running, the threads are then joined.

      def fetch
        Chore.logger.info "TCS: Starting up: #{self.class.name}"
        threads = []
        Chore.config.queues.each do |consume_queue|
          Chore.logger.info "TCS: Starting #{@consumers_per_queue} threads for Queue #{consume_queue}"
          @consumers_per_queue.times do
            next unless running?
            threads << consume(consume_queue)
          end
        end
        threads.each(&:join)
      end

      # If the ThreadedConsumerStrategy is currently running <tt>stop!</tt>
      # will begin signalling it to stop. It will stop the batcher
      # from forking more work,as well as set a flag which will disable
      # it's own consuming threads once they finish with their current work.
      def stop!
        if running?
          Chore.logger.info "TCS: Shutting down fetcher: #{self.class.name}"
          @running = false
          @consumers.each do |consumer|
            Chore.logger.info "TCS: Stopping consumer: #{consumer.object_id}"
            @queue.clear
            consumer.stop
          end
        end
      end

      # Returns whether or not the ThreadedConsumerStrategy is running or not
      def running?
        @running
      end

      # return upto number_of_free_workers work objects
      def provide_work(no_free_workers)
        work_units = []
        free_workers = [no_free_workers, @queue.size].min
        while free_workers > 0
          work_units << @queue.pop
          free_workers -= 1
        end
        work_units
      end

      private

      def consume(consume_queue)
        consumer = Chore.config.consumer.new(consume_queue)
        @consumers << consumer
        start_consumer_thread(consumer)
      end

      # Starts a consumer thread for polling the given +consume_queue+.
      # If <tt>stop!<tt> is called, the threads will shut themsevles down.
      def start_consumer_thread(consumer)
        t = Thread.new(consumer) do |th|
          begin
            create_work_units(th)
          rescue Chore::TerribleMistake => e
            Chore.logger.error 'Terrible mistake, shutting down Chore'
            Chore.logger.error "#{e.inspect} at #{e.backtrace}"
            @fetcher.manager.shutdown!
          end
        end
        t
      end

      def create_work_units(consumer)
        consumer.consume do |id, queue, timeout, body, previous_attempts|
          # Note: The unit of work object contains a consumer object that when 
          # used to consume from SQS, would have a mutex (that comes as a part 
          # of the AWS sdk); When sending these objects across from one process 
          # to another, we cannot send this across (becasue of the mutex). To 
          # work around this, we simply ignore the consumer object when creating
          # the unit of work object, and when the worker recieves the work 
          # object, it assigns it a consumer object. 
          # (to allow for communication back to the queue it was consumed from)
          work = UnitOfWork.new(id, queue, timeout, body,
                                previous_attempts)
          Chore.run_hooks_for(:consumed_from_source, work)
          @queue.push(work) if running?
          Chore.run_hooks_for(:added_to_queue, work)
        end
      end
    end # ThrottledConsumerStrategyyeah 
  end
end # Chore
