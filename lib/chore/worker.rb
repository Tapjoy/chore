require 'chore/util'
require 'chore/json_encoder'

module Chore
  # Worker is one of the core classes in Chore. It's responsible for most of the logic
  # relating to actually processing a job. A given worker will take an amount of +work+
  # and then process it all until either the worker is told to stop, or the work is 
  # completed. Worker is completely agnostic to the WorkerStrategy that it was called from.
  class Worker
    include Util

    DEFAULT_OPTIONS = { :encoder => JsonEncoder }
    attr_accessor :options

    def self.start(work) #:nodoc:
      self.new(work).start
    end

    # Create a Worker. Give it an array of work (or single item), and +opts+.
    # Currently, the only option supported by Worker is +:encoder+ which should match
    # the +:encoder+ used by the Publisher who created the message.
    def initialize(work=[],opts={})
      @stopping = false
      @started_at = Time.now
      @work = work
      @work = [work] unless work.kind_of?(Array)
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    # The workhorse. Do the work, all of it. This will block for an entirely unspecified amount
    # of time based on the work to be performed. This will:
    # * Decode each message.
    # * Re-ify the messages into actual Job classes.
    # * Call Job#perform on each job.
    # * If successful it will call Consumer#complete (using the consumer in the UnitOfWork).
    # * If unsuccessful it will call the appropriate Hooks based on the type of failure.
    # * Log the results via the Chore.logger
    def start
      @work.each do |item|
        return if @stopping
        Chore.logger.debug { "Doing: #{item.inspect}" }
        begin
          message = decode_job(item.message)
          klass = payload_class(message)
          next unless klass.run_hooks_for(:before_perform,message)
          perform_job(item,klass,message)
        rescue => e
          Chore.logger.error { "Failed to run job #{item.inspect} with error: #{e.message} #{e.backtrace * "\n"}" }
          Chore.run_hooks_for(:on_failure,item.message,e)
        end
      end
    end

    # Tell the worker to stop after it completes the current job.
    def stop!
      @stopping = true
    end

  protected
    def payload_class(message)
      constantize(message['class'])
    end

  private
    def perform_job(item,klass, message)
      klass.perform(*message['args'])
      item.consumer.complete(item.id)
      klass.run_hooks_for(:after_perform,message)
    rescue Job::RejectMessageException
      item.consumer.reject(item.id)
      Chore.logger.error { "Failed to run job #{item.inspect} with error: Job raised a RejectMessageException" }
      klass.run_hooks_for(:on_rejected, message)
    rescue => e
      Chore.logger.error { "Failed to run job #{item.inspect} with error: #{e.message} at #{e.backtrace * "\n"}" }
      klass.run_hooks_for(:on_failure,message,e)
    end

    def decode_job(data)
      options[:encoder].decode(data)
    end
  end
end
