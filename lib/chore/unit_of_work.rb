module Chore
  # Simple class to hold job processing information.
  # Has only four attributes:
  # * +:id+ The queue implementation specific identifier for this message.
  # * +:message+ The actual data of the message.
  # * +:previous_attempts+ The number of times the work has been attempted previously.
  # * +:consumer+ The consumer instance used to fetch this message. Most queue implementations won't need access to this, but some (RabbitMQ) will. So we
  # make sure to pass it along with each message. This instance will be used by the Worker for things like <tt>complete</tt> and </tt>reject</tt>.
  class UnitOfWork < Struct.new(:id,:queue_name,:message,:previous_attempts,:consumer)
    # The current attempt number for the worker processing this message.
    def current_attempt
      previous_attempts + 1
    end
  end
end