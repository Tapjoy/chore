require 'thread/pool'

module Chore
  module Queues
    module SQS
      class BatchSendingPool < Thread::Pool
        def initialize(size)
          @run = true
          # Thread::Pool supports multiple arguments on the initialize method.
          # Passing in a single number creates a thread pool that is fixed to that number.
          super(size)
          # auto_trim! just states that we will kill idle threads until we return to the specified minimum.
          # Because we only pass in one argument to initialize the pool, we will not grow beyond the minimum.
          # If, however, you pass a maximum thread pool size through, this will ensure you will not stay above
          # the minimum once you're done handling the surge 
          auto_trim!
          Chore.logger.info "sqs batch publishing pool initialized with #{size} threads"
        end
      end
    end
  end
end