require 'google/cloud/pubsub'
require 'chore/duplicate_detector'

module Chore
  module Queues
    module PubSub
      # GCP Pub/Sub Consumer for Chore. Requests messages from GCP Pub/Sub and passes them to be worked on.
      # Also controls acknowledging completed messages within GCP Pub/Sub.
      class Consumer < Chore::Consumer
        # Initialize the reset at on class load
        @@reset_at = Time.now

        Chore::CLI.register_option 'gcp_project_id', '--gcp-project-id PROJECT_ID', 'GCP Project ID for Pub/Sub' do |project_id|
          Chore::Queues::PubSub.project_id = project_id
        end
        
        Chore::CLI.register_option 'gcp_credentials', '--gcp-credentials PATH', 'Path to GCP service account credentials JSON file' do |credentials|
          Chore::Queues::PubSub.credentials = credentials
        end

        # Resets the API client connection and provides @@reset_at so we know when the last time that was done
        def self.reset_connection!
          @@reset_at = Time.now
        end

        # @param [String] queue_name Name of GCP Pub/Sub topic
        # @param [Hash] opts Options
        def initialize(queue_name, opts={})
          super(queue_name, opts)
          @subscription_name = "#{queue_name}-sub"
        end

        # Ensure that the consumer is capable of running
        def verify_connection!
          unless subscription.exists?
            raise "Subscription #{@subscription_name} does not exist"
          end
        end

        # Begins requesting messages from GCP Pub/Sub, which will invoke the +&handler+ over each message
        #
        # @param [Block] &handler Message handler, used by the calling context (worker) to create & assigns a UnitOfWork
        #
        # @return [Array<Google::Cloud::PubSub::ReceivedMessage>]
        def consume(&handler)
          while running?
            begin
              messages = handle_messages(&handler)
              sleep(Chore.config.consumer_sleep_interval) if messages.empty?
            rescue => e
              Chore.logger.error { "PubSubConsumer#consume: #{e.inspect} #{e.backtrace * "\n"}" }
            end
          end
        end

        # Unimplemented. Rejects the given message from GCP Pub/Sub.
        #
        # @param [String] message_id Unique ID of the Pub/Sub message
        #
        # @return nil
        def reject(message_id)
          # In Pub/Sub, we can simply not acknowledge the message and it will be redelivered
        end

        # Acknowledges the given message from the GCP Pub/Sub subscription
        #
        # @param [String] message_id Unique ID of the Pub/Sub message  
        # @param [String] ack_id Acknowledgment ID of the Pub/Sub message
        def complete(message_id, ack_id)
          Chore.logger.debug "Completing (acknowledging): #{message_id}"
          # Find the message by ack_id and acknowledge it
          if msg = @current_messages&.find { |m| m.ack_id == ack_id }
            msg.acknowledge!
          end
        end

        # Delays retry of a job by +backoff_calc+ seconds.
        # In Pub/Sub, we modify the ack deadline to delay the message
        #
        # @param [UnitOfWork] item Item to be delayed
        # @param [Block] backoff_calc Code that determines the backoff.
        def delay(item, backoff_calc)
          delay = backoff_calc.call(item)
          Chore.logger.debug "Delaying #{item.id} by #{delay} seconds"

          # Find the message and modify its ack deadline
          if msg = @current_messages&.find { |m| m.ack_id == item.receipt_handle }
            msg.modify_ack_deadline!(delay)
          end

          return delay
        end

        private

        # Requests messages from GCP Pub/Sub, and invokes the provided +&block+ over each one. Afterwards, the :on_fetch
        # hook will be invoked, per message
        #
        # @param [Block] &handler Message handler, passed along by #consume
        #
        # @return [Array<Google::Cloud::PubSub::ReceivedMessage>]
        def handle_messages(&block)
          begin
            verify_connection!
          rescue => e
            Chore.logger.error "There was a problem verifying the connection to the subscription: #{e.message}. Shutting down..."
            raise Chore::TerribleMistake
          end

          messages = subscription.pull(max: max_messages)
          @current_messages = messages
          received_timestamp = Time.now

          messages.each do |message|
            unless duplicate_message?(message.message_id, @subscription_name, queue_timeout, received_timestamp)
              # delivery_attempt is available but may be nil for older messages
              attempt_count = (message.delivery_attempt || 1) - 1
              block.call(message.message_id, message.ack_id, queue_name, queue_timeout, message.data, attempt_count, received_timestamp)
            end
            Chore.run_hooks_for(:on_fetch, message.ack_id, message.data)
          end

          messages
        end

        # Retrieves the GCP Pub/Sub subscription object. The method will cache the results to prevent round trips on subsequent calls
        #
        # If <tt>reset_connection!</tt> has been called, this will result in the connection being re-initialized,
        # as well as clear any cached results from prior calls
        #
        # @return [Google::Cloud::PubSub::Subscription]
        def subscription
          if !@pubsub_last_connected || (@@reset_at && @@reset_at >= @pubsub_last_connected)
            @pubsub = nil
            @pubsub_last_connected = Time.now
            @subscription = nil
          end

          @subscription ||= pubsub.subscriber(@subscription_name)
        end

        # The ack deadline (in seconds) of the subscription
        #
        # @return [Integer]
        def queue_timeout
          @queue_timeout ||= subscription.deadline || 600 # Default to 10 minutes
        end

        # GCP Pub/Sub client object
        #
        # @return [Google::Cloud::PubSub::Project]
        def pubsub
          @pubsub ||= Chore::Queues::PubSub.pubsub_client
        end

        # Maximum number of messages to retrieve on each request
        #
        # @return [Integer]
        def max_messages
          [pubsub_polling_amount, 1000].min  # Pub/Sub max is 1000
        end

        # Maximum number of messages to retrieve on each request from config
        #
        # @return [Integer]
        def pubsub_polling_amount
          Chore.config.queue_polling_size
        end
      end
    end
  end
end 
