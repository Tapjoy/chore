module Chore
  module Strategy 
    class Batcher #:nodoc:
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

      def schedule(batch_timeout=20)
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

      def add(item)
        @batch << item
        @last_message = Time.now
        execute if ready?
      end

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

      def ready?
        @batch.size >= @size
      end

      def stop
        @running = false
      end
    end
  end
end