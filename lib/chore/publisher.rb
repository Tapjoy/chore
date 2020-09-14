module Chore
  # Base class for a Chore Publisher. Provides the interface that a Chore::Publisher implementation should adhere to.
  class Publisher
    DEFAULT_OPTIONS = { :encoder => Encoder::JsonEncoder }

    attr_accessor :options

    # @param [Hash] opts
    def initialize(opts={})
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    # Publishes the provided +job+ to the queue identified by the +queue_name+. Not designed to be used directly, this
    # method ferries to the publish method on an instance of your configured Publisher.
    #
    # @param [String] queue_name Name of queue to be consumed from
    # @param [Hash] job Job instance definition, will be encoded to JSON
    def self.publish(queue_name,job)
      self.new.publish(queue_name,job)
    end

    # Publishes a message to queue
    #
    # @param [String] queue_name Name of the SQS queue
    # @param [Hash] job Job instance definition, will be encoded to JSON
    def publish(queue_name,job)
      raise NotImplementedError
    end

    # Sets a flag that instructs the publisher to reset the connection the next time it's used.
    # Should be overriden in publishers (but is not required)
    def self.reset_connection!
    end

  protected

    # Encodes the job class to format provided by endoder implementation
    #
    # @param [Any] job
    def encode_job(job)
      options[:encoder].encode(job)
    end

  end
end
