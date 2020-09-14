require 'chore/hooks'
require 'chore/util'
require 'chore/encoders/json_encoder'

module Chore

  # <tt>Chore::Job</tt> is the module which gives your job classes the methods they need to be published
  # and run within Chore. You cannot have a Job in Chore that does not include this module
  module Job
    extend Util

    # An exception to represent a job choosing to forcibly reject a given instance of itself.
    # The reasoning behind rejecting the job and the message that spawned it are left to
    # the developer to dedide to use or not to use.
    class RejectMessageException < Exception
      # Throw a RejectMessageException from your job to signal that the message should be rejected.
      # The semantics of +reject+ are queue implementation dependent.
    end

    def self.job_classes #:nodoc:
      @classes || []
    end

    def self.included(base) #:nodoc:
      @classes ||= []
      @classes << base.name
      base.extend(ClassMethods)
      base.extend(Hooks)
    end

    def self.payload_class(message)
      constantize(message['class'])
    end

    def self.decode(data)
      Encoder::JsonEncoder.decode(data)
    end

    def self.payload(message)
      message['args']
    end

    module ClassMethods
      DEFAULT_OPTIONS = { }

      # Pass a hash of options to queue_options the included class's use of Chore::Job
      # +opts+ has just the one required option.
      # * +:name+: which should map to the name of the queue this job should be published to.
      def queue_options(opts = {})
        @chore_options = (@chore_options || DEFAULT_OPTIONS).merge(opts_from_cli).merge(opts)

        required_options.each do |k|
          raise ArgumentError.new("#{self.to_s} :#{k} is a required option for Chore::Job") unless @chore_options[k]
        end

        if @chore_options.key?(:backoff)
          if !@chore_options[:backoff].is_a?(Proc)
            raise ArgumentError, "#{self.to_s}: backoff must be a lambda or Proc"
          elsif @chore_options[:backoff].arity != 1
            raise ArgumentError, "#{self.to_s}: backoff must accept a single argument"
          end
        end

        if @chore_options.key?(:dedupe_lambda)
          if !@chore_options[:dedupe_lambda].is_a?(Proc)
            raise ArgumentError, "#{self.to_s}: dedupe_lambda must be a lambda or Proc"
          end
        end
      end

      # This is a method so it can be overriden to create additional required
      # queue_options params.  This also determines what options get pulled
      # from the global Chore.config.
      def required_options
        [:name, :publisher, :max_attempts]
      end

      def options #:nodoc:#
        @chore_options ||= queue_options
      end

      def opts_from_cli #:nodoc:#
        @from_cli ||= (Chore.config.marshal_dump.select {|k,v| required_options.include? k } || {})
      end

      # Execute the current job. We create an instance of the job to do the perform
      # as this allows the jobs themselves to do initialization that might require access
      # to the parameters of the job.
      def perform(*args)
        job = self.new(args)
        job.perform(*args)
      end

      # Publish a job using an instance of job. Similar to perform we do this so that a job
      # can perform initialization logic before the perform_async is begun. This, in addition, to
      # hooks allows for rather complex jobs to be written simply.
      def perform_async(*args)
        job = self.new(args)
        job.perform_async(*args)
      end

      # Resque/Sidekiq compatible serialization. No reason to change what works
      def job_hash(job_params)
        {:class => self.to_s, :args => job_params}
      end

      # The name of the configured queue, combined with an optional prefix
      #
      # @return [String]
      def prefixed_queue_name
        "#{Chore.config.queue_prefix}#{self.options[:name]}"
      end

      # We require a proc for the backoff strategy, but as we check for it in `.queue_options` we can simply check for
      # the key at this point.
      def has_backoff?
        self.options.key?(:backoff)
      end

      def has_dedupe_lambda?
        self.options.key?(:dedupe_lambda)
      end

      def dedupe_key(*args)
        return unless has_dedupe_lambda?

        # run the proc to get the key
        self.options[:dedupe_lambda].call(*args).to_s
      end
    end #ClassMethods

    # This is handy to override in an included job to be able to do job setup that requires
    # access to a job's arguments to be able to perform any context specific initialization that may
    # be required.
    def initialize(args=nil)
    end

    # This needs to be overriden by the object that is including this module.
    def perform(*args)
      raise NotImplementedError
    end

    # Use the current configured publisher to send this job into a queue.
    def perform_async(*args)
      self.class.run_hooks_for(:before_publish,*args)
      @chore_publisher ||= self.class.options[:publisher]
      @chore_publisher.publish(self.class.prefixed_queue_name,self.class.job_hash(args))
      self.class.run_hooks_for(:after_publish,*args)
    end

  end #Job
end #Chore
