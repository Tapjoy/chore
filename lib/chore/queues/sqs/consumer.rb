require 'aws-sdk-sqs'
require 'chore/duplicate_detector'

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

        # Resets the API client connection and provides @@reset_at so we know when the last time that was done
        def self.reset_connection!
          @@reset_at = Time.now
        end

        # @param [String] queue_name Name of SQS queue
        # @param [Hash] opts Options
        def initialize(queue_name, opts={})
          super(queue_name, opts)
          raise Chore::TerribleMistake, "Cannot specify a queue polling size greater than 10" if sqs_polling_amount > 10
        end

        # Ensure that that consumer is capable of running
        def verify_connection!
          queue.data
        end

        # Begins requesting messages from SQS, which will invoke the +&handler+ over each message
        #
        # @param [Block] &handler Message handler, used by the calling context (worker) to create & assigns a UnitOfWork
        #
        # @return [Array<Aws::SQS::Message>]
        def consume(&handler)
          while running?
            begin
              messages = handle_messages(&handler)
              sleep (Chore.config.consumer_sleep_interval) if messages.empty?
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
        # @param [Hash] receipt_handle Receipt handle (unique per consume request) of the SQS message
        def complete(message_id, receipt_handle)
          Chore.logger.debug "Completing (deleting): #{message_id}"
          queue.delete_messages(entries: [{ id: message_id, receipt_handle: receipt_handle }])
        end

        # Delays retry of a job by +backoff_calc+ seconds.
        #
        # @param [UnitOfWork] item Item to be delayed
        # @param [Block] backoff_calc Code that determines the backoff.
        def delay(item, backoff_calc)
          delay = backoff_calc.call(item)
          Chore.logger.debug "Delaying #{item.id} by #{delay} seconds"

          queue.change_message_visibility_batch(entries: [
            { id: item.id, receipt_handle: item.receipt_handle, visibility_timeout: delay },
          ])

          return delay
        end

        private

        # Requests messages from SQS, and invokes the provided +&block+ over each one. Afterwards, the :on_fetch
        # hook will be invoked, per message
        #
        # @param [Block] &handler Message handler, passed along by #consume
        #
        # @return [Array<Aws::SQS::Message>]
        def handle_messages(&block)
          begin
            verify_connection!
          rescue => e
            # We shut down on connection failures for a few reasons:
            # * The AWS SQS client has already been configured to retry on temporal issues like authentication failures
            # * We rely on the operating system to re-run chore if it shuts down
            # * We don't want chore to keep spinning if there's an unrecoverable exception with the client;
            #   it's safest to restart chore in these situations
            Chore.logger.error "There was a problem verifying the connection to the queue: #{e.message}. Shutting down..."
            raise Chore::TerribleMistake
          end

          msg = queue.receive_messages(:max_number_of_messages => sqs_polling_amount, :attribute_names => ['ApproximateReceiveCount'])
          messages = *msg
          received_timestamp = Time.now

          messages.each do |message|
            unless duplicate_message?(message.message_id, message.queue_url, queue_timeout, received_timestamp)
              block.call(message.message_id, message.receipt_handle, queue_name, queue_timeout, message.body, message.attributes['ApproximateReceiveCount'].to_i - 1, received_timestamp)
            end
            Chore.run_hooks_for(:on_fetch, message.receipt_handle, message.body)
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
            Aws.empty_connection_pools!
            @sqs = nil
            @sqs_last_connected = Time.now
            @queue = nil
          end

          @queue_url ||= sqs.get_queue_url(queue_name: @queue_name).queue_url
          @queue ||= Aws::SQS::Queue.new(url: @queue_url, client: sqs)
        end

        # The visibility timeout (in seconds) of the queue
        #
        # @return [Integer]
        def queue_timeout
          @queue_timeout ||= queue.attributes['VisibilityTimeout'].to_i
        end

        # SQS API client object
        #
        # @return [Aws::SQS::Client]
        def sqs
          @sqs ||= Chore::Queues::SQS.sqs_client
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
