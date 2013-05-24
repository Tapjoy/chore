module Chore
  class Consumer

    attr_accessor :queue_name

    def initialize(queue_name, opts={})
      @queue_name = queue_name
      @running = true
    end

    #
    # Causes the underlying connection for all consumers of this class to be reset. Useful for the case where
    # the consumer is being used across a fork. Should be overriden in consumers (but is not required).
    #
    def self.reset_connection!
    end

    #
    # Consume takes a block with an arity of two. The two params are
    # |message_id,message_body| where message_id is any object that the
    # consumer will need to be able to act on a message later (reject, complete, etc)
    #
    def consume(&block)
      raise NotImplementedError
    end

    #
    # Reject should put a message back on a queue to be processed again later. It takes
    # a message_id as returned via consume.
    #
    def reject(message_id)
      raise NotImplementedError
    end

    #
    # Complete should mark a message as finished. It takes a message_id as returned via consume
    #
    def complete(message_id)
      raise NotImplementedError
    end

    #
    # Perform any shutdown behavior and stop consuming messages
    #
    def stop
      @running = false
    end

    def running?
      @running
    end
  end
end
