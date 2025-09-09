require 'chore/publisher'

module Chore
  module Queues
    module PubSub
      # GCP Pub/Sub Publisher, for writing messages to GCP Pub/Sub from Chore
      class Publisher < Chore::Publisher
        # @param [Hash] opts Publisher options
        def initialize(opts={})
          super
          @pubsub_publisher = {}
        end

        # Publishes a message to a GCP Pub/Sub topic
        #
        # @param [String] queue_name Name of the GCP Pub/Sub topic
        # @param [Hash] job Job instance definition, will be encoded to JSON
        #
        # @return [Google::Cloud::PubSub::Message]
        def publish(queue_name, job)
          publisher = get_publisher(queue_name)
          encoded_job = encode_job(job)
          publisher.publish(encoded_job)
        end


        private

        # GCP Pub/Sub client object
        #
        # @return [Google::Cloud::PubSub::Project]
        def pubsub
          @pubsub ||= Chore::Queues::PubSub.pubsub_client
        end

        # Retrieves the GCP Pub/Sub publisher object. The method will cache the results to prevent round trips on subsequent calls
        #
        # @param [String] name Name of GCP Pub/Sub topic 
        #
        # @return [Google::Cloud::PubSub::Publisher]
        def get_publisher(name) 
          @pubsub_publisher[name] ||= pubsub.publisher(name)
        end
      end
    end
  end
end 
