require 'aws/sqs'
require 'chore/duplicate_detector'

AWS.eager_autoload! AWS::Core
AWS.eager_autoload! AWS::SQS

module Chore
  module Queues
    module SQS
      # SQS Consumer for Chore. Requests messages from SQS and passes them to be worked on. Also controls
      # deleting completed messages within SQS.
      class Consumer < Chore::Consumer
        # Initialize the reset at on class load
        @@reset_at = Time.now

        Chore::CLI.register_option 'aws_access_key', '--aws-access-key KEY', 'Valid AWS Access Key'
        Chore::CLI.register_option 'aws_secret_key', '--aws-secret-key KEY', 'Valid AWS Secret Key'
        Chore::CLI.register_option 'dedupe_servers', '--dedupe-servers SERVERS', 'List of mememcache compatible server(s) to use for storing SQS Message Dedupe cache'
        Chore::CLI.register_option 'queue_polling_size', '--queue_polling_size NUM', Integer, 'Amount of messages to grab on each request' do |arg|
          raise ArgumentError, "Cannot specify a queue polling size greater than 10" if arg > 10
        end

        def initialize(queue_name, opts={})
          super(queue_name, opts)
        end

        # Sets a flag that instructs the publisher to reset the connection the next time it's used
        def self.reset_connection!
          @@reset_at = Time.now
        end

        # Begins requesting messages from SQS, which will invoke the +&handler+ over each message
        def consume(&handler)
          while running?
            begin
              messages = handle_messages(&handler)
              sleep (Chore.config.consumer_sleep_interval || 1) if messages.empty?
            rescue AWS::SQS::Errors::NonExistentQueue => e
              Chore.logger.error "You specified a queue '#{queue_name}' that does not exist. You must create the queue before starting Chore. Shutting down..."
              raise Chore::TerribleMistake
            rescue => e
              Chore.logger.error { "SQSConsumer#Consume: #{e.inspect} #{e.backtrace * "\n"}" }
            end
          end
        end

        # Rejects the given message from SQS by +id+. Currently a noop
        def reject(id)

        end

        # Deletes the given message from SQS by +id+
        def complete(id)
          Chore.logger.debug "Completing (deleting): #{id}"
          queue.batch_delete([id])
        end

        def delay(item, backoff_calc)
          delay = backoff_calc.call(item)
          Chore.logger.debug "Delaying #{item.id} by #{delay} seconds"
          queue.batch_change_visibility(delay, [item.id])

          return delay
        end

        private

        # Requests messages from SQS, and invokes the provided +&block+ over each one. Afterwards, the :on_fetch
        # hook will be invoked, per message
        def handle_messages(&block)
          msg = queue.receive_messages(:limit => sqs_polling_amount, :attributes => [:receive_count])
          messages = *msg
          messages.each do |message|
            unless duplicate_message?(message)
              block.call(message.handle, queue_name, queue_timeout, message.body, message.receive_count - 1)
            end
            Chore.run_hooks_for(:on_fetch, message.handle, message.body)
          end
          messages
        end

        # Checks if the given message has already been received within the timeout window for this queue
        def duplicate_message?(message)
          dupe_detector.found_duplicate?(:id=>message.id, :queue=>message.queue.url, :visibility_timeout=>message.queue.visibility_timeout)
        end

        # Returns the instance of the DuplicateDetector used to ensure unique messages.
        # Will create one if one doesn't already exist
        def dupe_detector
          @dupes ||= DuplicateDetector.new({:servers => Chore.config.dedupe_servers,
                                            :dupe_on_cache_failure => Chore.config.dupe_on_cache_failure})
        end

        # Retrieves the SQS queue with the given +name+. The method will cache the results to prevent round trips on
        # subsequent calls. If <tt>reset_connection!</tt> has been called, this will result in the connection being
        # re-initialized, as well as clear any cached results from prior calls
        def queue
          if !@sqs_last_connected || (@@reset_at && @@reset_at >= @sqs_last_connected)
            AWS::Core::Http::ConnectionPool.pools.each do |p|
              p.empty!
            end
            @sqs = nil
            @sqs_last_connected = Time.now
            @queue = nil
          end
          @queue_url ||= sqs.queues.url_for(@queue_name)
          @queue ||= sqs.queues[@queue_url]
        end

        # The visibility timeout of the queue for this consumer
        def queue_timeout
          @queue_timeout ||= queue.visibility_timeout
        end

        # Access to the configured SQS connection object
        def sqs
          @sqs ||= AWS::SQS.new(
            :access_key_id => Chore.config.aws_access_key,
            :secret_access_key => Chore.config.aws_secret_key,
            :logger => Chore.logger,
            :log_level => Chore.config.log_level)
        end

        def sqs_polling_amount
          Chore.config.queue_polling_size || 10
        end
      end
    end
  end
end
