require 'chore/publisher'

module Chore
  module Queues
    module PubSub
      # GCP Pub/Sub Publisher, for writing messages to GCP Pub/Sub from Chore
      class Publisher < Chore::Publisher
        @@reset_next = true

        # @param [Hash] opts Publisher options
        def initialize(opts={})
          super
          @pubsub_topics = {}
        end

        # Publishes a message to a GCP Pub/Sub topic
        #
        # @param [String] queue_name Name of the GCP Pub/Sub topic
        # @param [Hash] job Job instance definition, will be encoded to JSON
        #
        # @return [Google::Cloud::PubSub::Message]
        def publish(queue_name, job)
          topic = get_topic(queue_name)
          encoded_job = encode_job(job)
          topic.publish(encoded_job)
        end

        # Sets a flag that instructs the publisher to reset the connection the next time it's used
        def self.reset_connection!
          @@reset_next = true
        end

        private

        # GCP Pub/Sub client object
        #
        # @return [Google::Cloud::PubSub::Project]
        def pubsub
          @pubsub ||= Chore::Queues::PubSub.pubsub_client
        end

        # Retrieves the GCP Pub/Sub topic object. The method will cache the results to prevent round trips on subsequent calls
        #
        # If <tt>reset_connection!</tt> has been called, this will result in the connection being re-initialized,
        # as well as clear any cached results from prior calls
        #
        # @param [String] name Name of GCP Pub/Sub topic
        #
        # @return [Google::Cloud::PubSub::Topic]
        def get_topic(name)
          if @@reset_next
            @pubsub = nil
            @@reset_next = false
            @pubsub_topics = {}
          end

          @pubsub_topics[name] ||= pubsub.topic(name)
        end
      end
    end
  end
end 