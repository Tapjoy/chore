require 'chore/publisher'

module Chore
  module Queues
    module SQS

      # SQS Publisher, for writing messages to SQS from Chore
      class Publisher < Chore::Publisher
        @@reset_next = true

        def initialize(opts={})
          super
          @sqs_queues = {}
          @sqs_queue_urls = {}
        end

        # Takes a given Chore::Job instance +job+, and publishes it by looking up the +queue_name+.
        def publish(queue_name, job, options={})
          delay_seconds = options[:delay]
          options = {}

          # SQS only supports a delay range of 0-900 seconds. Make sure we're in the range. We also only put it into the
          # options Hash if its set to prevent any weird SQS behaviors.
          # NOTE may be okay pushing the key with a `nil` value...
          if delay_seconds
            if delay_seconds < 0
              delay_seconds = 0
            elsif delay_seconds > 900
              Chore.logger.warn("SQS does not support a delay longer than 15 minutes (900 seconds)! " <
                                "Reducing the delay to the maximum supported.")
              delay_seconds = 900
            end

            options[:delay_seconds] = delay_seconds
          end

          queue = self.queue(queue_name)
          queue.send_message(encode_job(job), options)
        end

        # Sets a flag that instructs the publisher to reset the connection the next time it's used
        def self.reset_connection!
          @@reset_next = true
        end

        # Access to the configured SQS connection object
        def sqs
          @sqs ||= AWS::SQS.new(
            :access_key_id => Chore.config.aws_access_key,
            :secret_access_key => Chore.config.aws_secret_key,
            :logger => Chore.logger,
            :log_level => :debug)
        end

        # Retrieves the SQS queue with the given +name+. The method will cache the results to prevent round trips on subsequent calls
        # If <tt>reset_connection!</tt> has been called, this will result in the connection being re-initialized,
        # as well as clear any cached results from prior calls
        def queue(name)
         if @@reset_next
            AWS::Core::Http::ConnectionPool.pools.each do |p|
              p.empty!
            end
            @sqs = nil
            @@reset_next = false
            @sqs_queues = {}
          end
          @sqs_queue_urls[name] ||= self.sqs.queues.url_for(name)
          @sqs_queues[name] ||= self.sqs.queues[@sqs_queue_urls[name]]
        end
      end
    end
  end
end
