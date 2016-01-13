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
      self.options = {
        :payload_handler => Chore.config.payload_handler,
        :process_in_batches => false
      }.merge(opts)
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
      if self.options[:process_in_batches] == true
        start_work_in_batches
      else
        start_work
      end
    end

    # This method will perform the traditional behavior of doing the work one by one
    # A single message will be handed to a single job class for processing.
    def start_work
      @work.each do |item|
        return if @stopping
        begin
          item.decoded_message = options[:payload_handler].decode(item.message)
          item.klass = options[:payload_handler].payload_class(item.decoded_message)
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

    # This method will perform a batching operation, where all the messages for a given
    # job class will be grouped together by that class, and handed to it in a single batch.
    # This is a special use case, only to be used when the performance benefits of
    # running multiple jobs as one makes sense.
    def start_work_in_batches
      # First, we need to deserialize the message payloads
      @work.each {|item| item.decoded_message = options[:payload_handler].decode(item.message)}
      # Now, because a single queue could theoretically contain different job payloads,
      # we need to group the results by job type
      work_groups = @work.group_by {|item| item.klass = options[:payload_handler].payload_class(item.decoded_message)}
      # We now have a hash of JobClass => Array of payloads to run
      work_groups.each do |klass, items|
        return if @stopping
        begin
          start_batched_items(klass, items)
        rescue => e
          Chore.logger.error { "Failed to run batched-jobs for #{items.map(&:message).join("\n")} with error: #{e.message} #{e.backtrace * "\n"}" }
          items.each do |item|
            if item.current_attempt >= Chore.config.max_attempts
              Chore.run_hooks_for(:on_permanent_failure,item.queue_name,item.message,e)
              item.consumer.complete(item.id)
            else
              Chore.run_hooks_for(:on_failure,item.message,e)
            end
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
        perform_job(klass,message)
        item.consumer.complete(item.id)
        Chore.logger.info { "Finished job #{klass} with params #{message}"}
        klass.run_hooks_for(:after_perform, message)
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

    def start_batched_items(klass, items)
      items.each {|item| return unless item.klass.run_hooks_for(:before_perform,item.message)}
      logged_batch_payload = items.map(&:message).join("\n")
      begin
        Chore.logger.info { "Running job #{klass} with params #{logged_batch_payload}"}
        perform_batch_job(klass,items.map(&:decoded_message))
        items.each do |item|
          item.consumer.complete(item.id)
          klass.run_hooks_for(:after_perform, item.decoded_message)
        end
        Chore.logger.info { "Finished job #{klass} with params #{logged_batch_payload}"}
      rescue Job::RejectMessageException
        Chore.logger.error { "Failed to run job for #{logged_batch_payload}  with error: Job raised a RejectMessageException" }
        items.each do |item|
          item.consumer.reject(item.id)
          klass.run_hooks_for(:on_rejected, item.decoded_message)
        end
      rescue => e
        items.each do |item|
          if klass.has_backoff?
            attempt_to_delay(item, item.decoded_message, klass)
          else
            handle_failure(item, item.decoded_message, klass, e)
          end
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
        item.consumer.complete(item.id)
      else
        klass.run_hooks_for(:on_failure, message, e)
      end
    end

    def perform_job(klass, message)
      klass.perform(*options[:payload_handler].payload(message))
    end

    def perform_batch_job(klass, messages)
      klass.perform(messages.flat_map {|m|options[:payload_handler].payload(m)})
    end
  end
end
