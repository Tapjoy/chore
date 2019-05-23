module Chore
  # Raised when Chore is booting up, but encounters a set of configuration that is impossible to boot from. Typically
  # you'll find additional information around the cause of the exception by examining the logfiles
  class TerribleMistake < Exception
    # You can raise this exception if your queue is in a terrible state and must shut down
  end

  # Base class for a Chore Consumer. Provides the basic interface to adhere to for building custom
  # Chore Consumers.
  class Consumer

    attr_accessor :queue_name

    def initialize(queue_name, opts={})
      @queue_name = queue_name
      @running = true
    end

    # Causes the underlying connection for all consumers of this class to be reset. Useful for the case where
    # the consumer is being used across a fork. Should be overriden in consumers (but is not required).
    def self.reset_connection!
    end

    # Consume takes a block with an arity of two. The two params are
    # |message_id,message_body| where message_id is any object that the
    # consumer will need to be able to act on a message later (reject, complete, etc)
    def consume(&block)
      raise NotImplementedError
    end

    # Reject should put a message back on a queue to be processed again later. It takes
    # a message_id as returned via consume.
    def reject(message_id)
      raise NotImplementedError
    end

    # Complete should mark a message as finished. It takes a message_id as returned via consume
    def complete(message_id)
      raise NotImplementedError
    end

    # Perform any shutdown behavior and stop consuming messages
    def stop
      @running = false
    end

    # Returns true if the Consumer is currently running
    def running?
      @running
    end

    # returns up to n work
    def provide_work(n)
      raise NotImplementedError
    end

    # now, given an arbitrary key and klass, have we seen the key already?
    def duplicate_message?(dedupe_key, klass, queue_timeout)
      dupe_detector.found_duplicate?(:id=>dedupe_key, :queue=>klass.to_s, :visibility_timeout=>queue_timeout)
    end

    def dupe_detector
      @dupes ||= DuplicateDetector.new({:servers => Chore.config.dedupe_servers,
                                        :dupe_on_cache_failure => false})
    end
  end
end
