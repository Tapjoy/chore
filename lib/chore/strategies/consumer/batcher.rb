module Chore
  module Strategy

    # Handles holding jobs in memory until such time as the batch has become full, per the developers configured threshold,
    # or enough time elapses that Chore determines to not wait any longer (20 seconds by default)
    class Batcher
      attr_accessor :callback
      attr_accessor :batch

      def initialize(size)
        @size = size
        @batch = []
        @mutex = Mutex.new
        @callback = nil
        @running = true
      end

      # The main entry point of the Batcher, <tt>schedule</tt> begins a thread with the provided +batch_timeout+
      # as the only argument. While the Batcher is running, it will attempt to check if either the batch is full,
      # or if the +batch_timeout+ has elapsed since the oldest message was added. If either case is true, the
      # items in the batch will be executed.
      #
      # Calling <tt>stop</tt> will cause the thread to finish it's current check, and exit
      def schedule(batch_timeout)
        @thread = Thread.new(batch_timeout) do |timeout|
          Chore.logger.info "Batching thread starting with #{batch_timeout} second timeout"
          while @running do
            begin
              oldest_item = @batch.first
              timestamp = oldest_item && oldest_item.created_at
              Chore.logger.debug "Oldest message in batch: #{timestamp}, size: #{@batch.size}"
              if timestamp && Time.now > (timestamp + timeout)
                Chore.logger.debug "Batching timeout reached (#{timestamp + timeout}), current size: #{@batch.size}"
                self.execute(true)
              end
              sleep(1)
            rescue => e
              Chore.logger.error "Batcher#schedule raised an exception: #{e.inspect}"
            end
          end
        end
      end

      # Adds the +item+ to the current batch
      def add(item)
        @batch << item
        execute if ready?
      end

      # Calls for the batch to be executed. If +force+ is set to true, the batch will execute even if it is not full yet
      def execute(force = false)
        batch = nil
        @mutex.synchronize do
          if force || ready?
            batch = @batch.slice!(0...@size)
          end
        end

        if batch && !batch.empty?
          @callback.call(batch)
        end
      end

      # Determines if the batch is ready to fire, by comparing it's size to the configured batch_size
      def ready?
        @batch.size >= @size
      end

      # Sets a flag which will begin shutting down the Batcher
      def stop
        @running = false
      end
    end
  end
end
