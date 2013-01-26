module Chore
  module Job

    def self.included(base)
      @classes ||= []
      @classes << base.name
      base.extend(ClassMethods)
    end

    module ClassMethods
      DEFAULT_OPTIONS = { :encoder => JsonEncoder }

      def configure(opts = {})
        @chore_options = (@chore_options || DEFAULT_OPTIONS).merge(opts)
        required_options.each do |k|
          raise ArgumentError.new(":#{k} is required") unless @chore_options[k]
        end
      end

      def required_options
        [:queue,:publisher]
      end

      def options
        @chore_options ||= configure
      end

      def perform(*args)
        job = self.new(args)
        job.perform(*args)
      end

      def publish(*args)
        job = self.new(args)
        job.publish(*args)
      end

      def job_hash(job_params)
        {:job => self.to_s, :params => job_params}
      end
    end #ClassMethods

    ## This is handy to override in an included job to be able to do job setup that requires
    ## access to a job's arguments to be able to perform
    def initialize(args=nil)
    end

    def setup
    end

    def perform(*args)
      raise NotImplementedError
    end

    def publish(*args)
      @chore_publisher ||= self.class.options[:publisher].new
      @chore_publisher.publish(self.class.job_hash(args))
    end

  end #Job
end #Chore
