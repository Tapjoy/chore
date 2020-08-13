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

        # @param [String] queue_name Name of SQS queue
        # @param [Hash] opts Options
        def initialize(queue_name, opts={})
          super(queue_name, opts)
          raise Chore::TerribleMistake, "Cannot specify a queue polling size greater than 10" if sqs_polling_amount > 10
        end

        # Sets a flag that instructs the publisher to reset the connection the next time it's used
        #
        # @return [Array<Seahorse::Client::NetHttp::ConnectionPool>]
        def self.reset_connection!
          @@reset_at = Time.now
          Aws.empty_connection_pools!
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
            rescue Aws::SQS::Errors::NonExistentQueue => e
              Chore.logger.error "You specified a queue '#{queue_name}' that does not exist. You must create the queue before starting Chore. Shutting down..."
              raise Chore::TerribleMistake
            rescue => e
              Chore.logger.error { "SQSConsumer#Consume: #{e.inspect} #{e.backtrace * "\n"}" }
            end
          end
        end

        # Unimplemented. Rejects the given message from SQS.
        #
        # @param [String] Unique ID of the SQS message
        #
        # @return nil
        def reject(id)
        end

        # Deletes the given message from the SQS queue
        #
        # @param [String] Unique ID of the SQS message
        # @param [Hash] opts Options, must include :receipt_handle (unique per consume request) of the SQS message
        #
        # @return [struct<Aws::SQS::Types::DeleteMessageBatchResult>]
        def complete(id, opts = {})
          Chore.logger.debug "Completing (deleting): #{id}"
          raise Chore::Consumer::CouldNotComplete, 'Required param "receipt_handle" missing!' unless opts[:receipt_handle]
          queue.delete_messages(entries: [{ id: id, receipt_handle: opts[:receipt_handle] }])
        end

        # Delays retry of a job by #{backoff_calc} seconds.
        #
        # @param [UnitOfWork] item Item to be delayed
        # @param [Proc?] backoff_calc Code that determines the backoff.
        #
        # @return [Numeric]
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
        # @param [Proc] &handler Message handler, passed along by #consume
        #
        # @return [Array<Aws::SQS::Message>]
        def handle_messages(&block)
          msg = queue.receive_messages(:max_number_of_messages => sqs_polling_amount, :attribute_names => ['ApproximateReceiveCount'])
          messages = *msg

          messages.each do |message|
            unless duplicate_message?(message.message_id, message.queue_url, queue_timeout)
              # This provides data necessary for the worker to populate the UnitOfWork struct
              block.call(message.message_id, message.receipt_handle, queue_name, queue_timeout, message.body, message.attributes['ApproximateReceiveCount'].to_i - 1)
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
        # @param [String] name Name of SQS queue
        #
        # @return [Aws::SQS::Queue]
        def queue
          if !@sqs_last_connected || (@@reset_at && @@reset_at >= @sqs_last_connected)
            self.class.reset_connection!
            @sqs = nil
            @sqs_last_connected = Time.now
            @queue = nil
          end

          @queue_url ||= sqs.get_queue_url(queue_name: @queue_name).queue_url
          @queue ||= Aws::SQS::Queue.new(url: @queue_url)
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
