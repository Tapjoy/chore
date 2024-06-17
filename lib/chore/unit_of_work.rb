module Chore
  # Simple class to hold job processing information.
  # Has six attributes:
  # * +:id+ The queue implementation specific identifier for this message.
  # * +:receipt_handle+ The queue implementation specific identifier for the receipt of this message.
  # * +:queue_name+ The name of the queue the job came from
  # * +:queue_timeout+ The time (in seconds) before the job will get re-enqueued if not processed
  # * +:message+ The actual data of the message.
  # * +:previous_attempts+ The number of times the work has been attempted previously.
  # * +:consumer+ The consumer instance used to fetch this message. Most queue implementations won't need access to this, but some (RabbitMQ) will. So we
  # make sure to pass it along with each message. This instance will be used by the Worker for things like <tt>complete</tt> and </tt>reject</tt>.
  class UnitOfWork < Struct.new(:id, :receipt_handle, :queue_name, :queue_timeout, :message, :previous_attempts, :consumer, :decoded_message, :klass, :received_timestamp)
    # The time at which this unit of work was created
    attr_accessor :created_at

    def initialize(*) #:nodoc:
      super
      @created_at = Time.now
    end

    # The current attempt number for the worker processing this message.
    def current_attempt
      previous_attempts + 1
    end
  end
end
