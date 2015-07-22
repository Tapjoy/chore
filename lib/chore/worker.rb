require 'chore/util'
require 'chore/job'

module Chore
  class TimeoutError < StandardError
  end

  # Worker is one of the core classes in Chore. It's responsible for most of the logic
  # relating to actually processing a job. A given worker will take an amount of +work+
  # and then process it all until either the worker is told to stop, or the work is
  # completed. Worker is completely agnostic to the WorkerStrategy that it was called from.
  class Worker
    include Util

    attr_accessor :options
    attr_reader   :work
    attr_reader   :started_at

    def self.start(work, opts={}) #:nodoc:
      self.new(work, opts).start
    end

    # Create a Worker. Give it an array of work (or single item), and +opts+.
    # Currently, the only option supported by Worker is +:payload_handler+ which contains helpers
    # for decoding the item and finding the correct payload class
    def initialize(work=[],opts={})
      @stopping = false
      @started_at = Time.now
      @work = work
      @work = [work] unless work.kind_of?(Array)
      self.options = {:payload_handler => Chore.config.payload_handler}.merge(opts)
    end

    # Whether this worker has existed for longer than it's allowed to
    def expired?
      Time.now > expires_at
    end

    # The time at which this worker expires
    def expires_at
      total_timeout = @work.inject(0) {|sum, item| sum += item.queue_timeout}
      @started_at + total_timeout
    end

    # The workhorse. Do the work, all of it. This will block for an entirely unspecified amount
    # of time based on the work to be performed. This will:
    # * Decode each message.
    # * Re-ify the messages into actual Job classes.
    # * Call Job#perform on each job.
    # * If successful it will call Consumer#complete (using the consumer in the UnitOfWork).
    # * If unsuccessful it will call the appropriate Hooks based on the type of failure.
    # * If unsuccessful *and* the maximum number of attempts for the job has been surpassed, it will call
    #   the permanent failure hooks and Consumer#complete.
    # * Log the results via the Chore.logger
    def start
      @work.each do |item|
        return if @stopping
        begin
          start_item(item)
        rescue => e
          Chore.logger.error { "Failed to run job for #{item.message} with error: #{e.message} #{e.backtrace * "\n"}" }
          if item.current_attempt >= Chore.config.max_attempts
            Chore.run_hooks_for(:on_permanent_failure,item.queue_name,item.message,e)
            item.consumer.complete(item.id)
          else
            Chore.run_hooks_for(:on_failure,item.message,e)
          end
        end
      end
    end

    # Tell the worker to stop after it completes the current job.
    def stop!
      @stopping = true
    end

  private
    def start_item(item)
      message = options[:payload_handler].decode(item.message)
      klass = options[:payload_handler].payload_class(message)
      return unless klass.run_hooks_for(:before_perform,message)

      begin
        Chore.logger.info { "Running job #{klass} with params #{message}"}
        perform_job(klass,message)
        item.consumer.complete(item.id)
        Chore.logger.info { "Finished job #{klass} with params #{message}"}
        klass.run_hooks_for(:after_perform, message)
      rescue Job::RejectMessageException
        item.consumer.reject(item.id)
        Chore.logger.error { "Failed to run job for #{item.message}  with error: Job raised a RejectMessageException" }
        klass.run_hooks_for(:on_rejected, message)
      rescue Job::DelayRetry
        delayed_for = item.consumer.delay(item, klass.options[:backoff])
        Chore.logger.info { "Delaying retry by #{delayed_for} seconds for the job #{item.message}" }
        klass.run_hooks_for(:on_delay, message)
      end
    # This rescue is outside above the `begin` scope so any issues with DelayThisJob handling will trigger a failure case
    rescue => e
      Chore.logger.error { "Failed to run job #{item.message} with error: #{e.message} at #{e.backtrace * "\n"}" }
      if item.current_attempt >= klass.options[:max_attempts]
        klass.run_hooks_for(:on_permanent_failure,item.queue_name,message,e)
        item.consumer.complete(item.id)
      else
        klass.run_hooks_for(:on_failure,message,e)
      end
    end

    def perform_job(klass, message)
      klass.perform(*options[:payload_handler].payload(message))
    end
  end
end
