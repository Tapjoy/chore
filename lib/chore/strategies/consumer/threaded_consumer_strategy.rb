require 'monitor'

module Chore
  module Strategy
    class Batcher #:nodoc:
      attr_accessor :callback
      attr_accessor :batch

      def initialize(size)
        @size = size
        @batch = []
        @mutex = Monitor.new
        @last_message = nil
        @callback = nil
      end

      def schedule(batch_timeout=20)
        Thread.new(batch_timeout) do |timeout|
          Chore.logger.info "Batching timeout thread starting"
          loop do
            begin 
              Chore.logger.debug "Last message added to batch: #{@last_message}: #{@batch.size}"
              if @last_message && Time.now > (@last_message + timeout)
                Chore.logger.debug "Batching timeout reached (#{@last_message + timeout}), current size: #{@batch.size}"
                self.execute
                @last_message = nil
              end
              sleep(1) 
            rescue => e
              Chore.logger.error "Batcher#schedule raised an exception: #{e.inspect}"
            end
          end
        end
      end

      def add(item)
        @mutex.synchronize do
          @batch << item
          @last_message = Time.now
          if @batch.size >= @size
            execute
          end
        end
      end

      def execute
        @mutex.synchronize do
          @callback.call(@batch)
          @batch.clear
        end
      end
    end

    class ThreadedConsumerStrategy
      attr_accessor :batcher

      Chore::CLI.register_option 'batch_size', '--batch-size SIZE', Integer, 'Number of items to collect for a single worker to process'
      Chore::CLI.register_option 'threads_per_queue', '--threads-per-queue NUM_THREADS', Integer, 'Number of threads to create for each named queue'

      def initialize(fetcher)
        @fetcher = fetcher
        @batcher = Batcher.new(Chore.config.batch_size)
        @batcher.callback = lambda { |batch| @fetcher.manager.assign(batch) }
        @batcher.schedule
        @running = true
      end

      def fetch
        Chore.logger.debug "Starting up consumer strategy: #{self.class.name}"
        threads = []
        Chore.config.queues.each do |queue|
          Chore.config.threads_per_queue.times do 
            threads << start_consumer_thread(queue)
          end
        end

        threads.each(&:join)
      end
      
      def stop!
        Chore.logger.info "Shutting down fetcher: #{self.class.name.to_s}"
        @running = false
      end

      def running?
        @running
      end

      private 
      def start_consumer_thread(queue)
        t = Thread.new(queue) do |tQueue|
          begin
            consumer = Chore.config.consumer.new(tQueue)
            consumer.consume do |id, body|
              # Quick hack to force this thread to end it's work
              # if we're shutting down. Could be delayed due to the
              # weird sometimes-blocking nature of SQS.
              consumer.stop if !running?
              Chore.logger.debug { "Got message: #{id}"}

              work = UnitOfWork.new(id, body, consumer)
              @batcher.add(work)
            end
          rescue => e
            Chore.logger.error "ThreadedConsumerStrategy#consumer thread raised an exception: #{e.inspect} at #{e.backtrace}"
          end
        end
        t
      end

    end #ThreadedConsumerStrategy
  end
end #Chore
