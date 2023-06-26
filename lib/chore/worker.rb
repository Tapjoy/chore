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

    def duplicate_work?(item)
      # if we've got a duplicate, remove the message from the queue by not actually running and also not reporting any errors
      payload = options[:payload_handler].payload(item.decoded_message)

       # if we're hitting the custom dedupe key, we want to remove this message from the queue
      if item.klass.has_dedupe_lambda?
        dedupe_key = item.klass.dedupe_key(*payload)
        if dedupe_key.nil? || dedupe_key.strip.empty? # if the dedupe key is nil, don't continue with the rest of the dedupe lambda logic
          Chore.logger.info { "#{item.klass} dedupe key nil, skipping memcached lookup." }
          return false
        end

        if item.consumer.duplicate_message?(dedupe_key, item.klass, item.queue_timeout)
          Chore.logger.info { "Found and deleted duplicate job #{item.klass}"}
          item.consumer.complete(item.id, item.receipt_handle)
          return true
        end
      end

      return false
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
          item.decoded_message = options[:payload_handler].decode(item.message)
          item.klass = options[:payload_handler].payload_class(item.decoded_message)

          next if duplicate_work?(item)

          Chore.run_hooks_for(:worker_to_start, item)
          start_item(item)
        rescue => e
          Chore.logger.error { "Failed to run job for #{item.message} with error: #{e.message} #{e.backtrace * "\n"}" }
          if item.current_attempt >= Chore.config.max_attempts
            Chore.run_hooks_for(:on_permanent_failure,item.queue_name,item.message,e)
            item.consumer.complete(item.id, item.receipt_handle)
          else
            Chore.run_hooks_for(:on_failure,item.message,e)
            item.consumer.reject(item.id)
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
      klass = item.klass
      message = item.decoded_message
      return unless klass.run_hooks_for(:before_perform, message)

      begin
        Chore.logger.info { "Running job #{klass} with params #{message}"}
        perform_job(klass, message)
        item.consumer.complete(item.id, item.receipt_handle)
        Chore.logger.info { "Finished job #{klass} with params #{message}"}
        klass.run_hooks_for(:after_perform, message)
        Chore.run_hooks_for(:worker_ended, item)
      rescue Job::RejectMessageException
        item.consumer.reject(item.id)
        Chore.logger.error { "Failed to run job for #{item.message}  with error: Job raised a RejectMessageException" }
        klass.run_hooks_for(:on_rejected, message)
      rescue => e
        if klass.has_backoff?
          attempt_to_delay(item, message, klass)
        else
          handle_failure(item, message, klass, e)
        end
      end
    end

    def attempt_to_delay(item, message, klass)
      delayed_for = item.consumer.delay(item, klass.options[:backoff])
      Chore.logger.info { "Delaying retry by #{delayed_for} seconds for the job #{item.message}" }
      klass.run_hooks_for(:on_delay, message)
    rescue => e
      handle_failure(item, message, klass, e)
    end

    def handle_failure(item, message, klass, e)
      Chore.logger.error { "Failed to run job #{item.message} with error: #{e.message} at #{e.backtrace * "\n"}" }
      if item.current_attempt >= klass.options[:max_attempts]
        klass.run_hooks_for(:on_permanent_failure,item.queue_name,message,e)
        item.consumer.complete(item.id, item.receipt_handle)
      else
        klass.run_hooks_for(:on_failure, message, e)
        item.consumer.reject(item.id)
      end
    end

    def perform_job(klass, message)
      Chore.run_hooks_for(:around_perform, klass, message) do
        klass.perform(*options[:payload_handler].payload(message))
      end
    end
  end
end
