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

        # @param [String] queue_name Name of SQS queue
        # @param [Hash] opts Options
        def initialize(queue_name, opts={})
          super(queue_name, opts)
          raise Chore::TerribleMistake, "Cannot specify a queue polling size greater than 10" if sqs_polling_amount > 10
        end

        # Resets the API client connection and provides @@reset_at so we know when the last time that was done
        #
        # @return [Array<Seahorse::Client::NetHttp::ConnectionPool>]
        def self.reset_connection!
          @@reset_at = Time.now
        end

        # Begins requesting messages from SQS, which will invoke the +&handler+ over each message
        #
        # @param [Proc] &handler Message handler, used by the calling context (worker) to create & assigns a UnitOfWork
        #
        # @return [Array<Aws::SQS::Message>]
        def consume(&handler)
          while running?
            begin
              messages = handle_messages(&handler)
              sleep (Chore.config.consumer_sleep_interval) if messages.empty?
            rescue AWS::SQS::Errors::NonExistentQueue => e
              Chore.logger.error "You specified a queue '#{queue_name}' that does not exist. You must create the queue before starting Chore. Shutting down..."
              raise Chore::TerribleMistake
            rescue => e
              Chore.logger.error { "SQSConsumer#Consume: #{e.inspect} #{e.backtrace * "\n"}" }
            end
          end
        end

        # Unimplemented. Rejects the given message from SQS.
        #
        # @param [String] message_id Unique ID of the SQS message
        #
        # @return nil
        def reject(message_id)
        end

        # Deletes the given message from the SQS queue
        #
        # @param [String] message_id Unique ID of the SQS message
        #
        # @return [struct<Aws::SQS::Types::DeleteMessageBatchResult>]
          Chore.logger.debug "Completing (deleting): #{id}"
          queue.batch_delete([id])
        end

        # Delays retry of a job by +backoff_calc+ seconds.
        #
        # @param [UnitOfWork] item Item to be delayed
        # @param [Proc] backoff_calc Code that determines the backoff.
        #
        # @return [Integer]
        def delay(item, backoff_calc)
          delay = backoff_calc.call(item)
          Chore.logger.debug "Delaying #{item.id} by #{delay} seconds"
          queue.batch_change_visibility(delay, [item.id])

          return delay
        end

        private

        # Requests messages from SQS, and invokes the provided +&block+ over each one. Afterwards, the :on_fetch
        # hook will be invoked, per message
        #
        # @param [Proc] &handler Message handler, passed along by #consume
        #
        # @return [Array<Aws::SQS::Message>]
        def handle_messages(&block)
          msg = queue.receive_messages(:limit => sqs_polling_amount, :attributes => [:receive_count])
          messages = *msg

          messages.each do |message|
            unless duplicate_message?(message.id, message.queue.url, queue_timeout)
              block.call(message.handle, queue_name, queue_timeout, message.body, message.receive_count - 1)
            end
            Chore.run_hooks_for(:on_fetch, message.handle, message.body)
          end

          messages
        end

        # Retrieves the SQS queue object. The method will cache the results to prevent round trips on subsequent calls
        #
        # If <tt>reset_connection!</tt> has been called, this will result in the connection being re-initialized,
        # as well as clear any cached results from prior calls
        #
        # @return [Aws::SQS::Queue]
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

        # The visibility timeout (in seconds) of the queue
        #
        # @return [Integer]
        def queue_timeout
          @queue_timeout ||= queue.visibility_timeout
        end

        # SQS API client object
        #
        # @return [Aws::SQS::Client]
        def sqs
          @sqs ||= AWS::SQS.new(
            :access_key_id => Chore.config.aws_access_key,
            :secret_access_key => Chore.config.aws_secret_key)
        end

        # Maximum number of messages to retrieve on each request
        #
        # @return [Integer]
        def sqs_polling_amount
          Chore.config.queue_polling_size
        end
      end
    end
  end
end
