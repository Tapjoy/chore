module Chore
  class Consumer

    attr_accessor :queue_name

    def initialize(queue_name, opts={})
      @queue_name = queue_name
      @running = true
    end

    def consume(&block)
      raise NotImplementedError
    end

    def reject(msg)
      raise NotImplementedError
    end

    def complete(msg)
      raise NotImplementedError
    end

    # Perform any shutdown behavior and stop consuming messages
    def stop
      @running = false
    end

    def running?
      @running
    end
  end
end
