module Chore
  # Base class for Chore Publishers. Provides the bare interface one needs to adhere to when writing custom publishers
  class Publisher
    DEFAULT_OPTIONS = { :encoder => Encoder::JsonEncoder }

    attr_accessor :options

    def initialize(opts={})
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    # Publishes the provided +job+ to the queue identified by the +queue_name+. Not designed to be used directly, this
    # method ferries to the publish method on an instance of your configured Publisher.
    def self.publish(queue_name, job, options={})
      self.new.publish(queue_name, job, options)
    end

    # Raises a NotImplementedError. This method should be overridden in your descendent, custom publisher class
    def publish(queue_name, job, options={})
      raise NotImplementedError
    end
  protected

    def encode_job(job)
      options[:encoder].encode(job)
    end

  end
end
