module Chore
  # Raised when Chore is booting up, but encounters a set of configuration that is impossible to boot from. Typically
  # you'll find additional information around the cause of the exception by examining the logfiles.
  # You can raise this exception if your queue is in a terrible state and must shut down.
  class TerribleMistake < Exception
  end

  # Base class for a Chore Consumer. Provides the interface that a Chore::Consumer implementation should adhere to.
  class Consumer

    attr_accessor :queue_name

    # Raise this exception if your message has been processed but you can't delete it from the queue.
    class CouldNotComplete < Exception; end

    # @param [String] queue_name Name of queue to be consumed from
    # @param [Hash] opts
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
    #
    # @param [Proc] &handler Message handler, used by the calling context (worker) to create & assigns a UnitOfWork
    def consume(&handler)
      raise NotImplementedError
    end

    # Reject should put a message back on a queue to be processed again later. It takes
    # a message_id as returned via consume.
    #
    # @param [String] message_id Unique ID of the message
    def reject(message_id)
      raise NotImplementedError
    end

    # Complete should mark a message as finished. It takes a message_id as returned via consume
    def complete(message_id)
      raise NotImplementedError
    end

    # Perform any shutdown behavior and stop consuming messages
    #
    # @return [FalseClass]
    def stop
      @running = false
    end

    # Returns true if the Consumer is currently running
    #
    # @return [TrueClass, FalseClass]
    def running?
      @running
    end

    # Returns up to n work
    #
    # @param n
    def provide_work(n)
      raise NotImplementedError
    end

    # Determine whether or not we have already seen this message
    #
    # @param [String] dedupe_key
    # @param [Class] klass
    # @param [Integer] queue_timeout
    #
    # @return [TrueClass, FalseClass]
    def duplicate_message?(dedupe_key, klass, queue_timeout)
      dupe_detector.found_duplicate?(:id=>dedupe_key, :queue=>klass.to_s, :visibility_timeout=>queue_timeout)
    end

    # Instance of duplicate detection implementation class
    #
    # @return [DuplicateDetector]
    def dupe_detector
      @dupes ||= DuplicateDetector.new({:servers => Chore.config.dedupe_servers,
                                        :dupe_on_cache_failure => false})
    end

    private

    # Gets messages from queue implementation and invokes the provided block over each one. Afterwards, the :on_fetch
    # hook will be invoked per message. This block call provides data necessary for the worker (calling context) to
    # populate a UnitOfWork struct.
    #
    # @param [Proc] &handler Message handler, passed along by #consume
    def handle_messages(&handler)
      raise NotImplementedError
    end
  end
end
