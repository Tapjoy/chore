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
        @last_message = nil
        @callback = nil
        @running = true
      end

      # The main entry point of the Batcher, <tt>schedule</tt> begins a thread with the provided +batch_timeout+ 
      # as the only argument. While the Batcher is running, it will attempt to check if either the batch is full, 
      # or if the +batch_timeout+ has elapsed since the last batch was executed. If the batch is full, it will be executed.
      # If the +batch_timeout+ has elapsed, as soon as the next message enters the batch, it will be executed.
      # 
      # Calling <tt>stop</tt> will cause the thread to finish it's current check, and exit
      def schedule(batch_timeout)
        @thread = Thread.new(batch_timeout) do |timeout|
          Chore.logger.info "Batching timeout thread starting"
          while @running do
            begin 
              Chore.logger.debug "Last message added to batch: #{@last_message}: #{@batch.size}"
              if @last_message && Time.now > (@last_message + timeout)
                Chore.logger.debug "Batching timeout reached (#{@last_message + timeout}), current size: #{@batch.size}"
                self.execute(true)
                @last_message = nil
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
        @last_message = Time.now
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
