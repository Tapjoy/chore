module Chore
  module Queues
    module PubSub
      REQUIRED_LIBRARY = "google/cloud/pubsub".freeze
      MIN_VERSION = Gem::Version.new('3.0.0')

      # Creates a configured PubSub client with the given options
      # Creates a GCP Pub/Sub client using global configuration
      def self.pubsub_client
        require REQUIRED_LIBRARY
        
        # Verify compatible version
        begin
          gem_version = Gem::Version.new(Google::Cloud::PubSub::VERSION)
          if gem_version && gem_version < MIN_VERSION
            raise "#{REQUIRED_LIBRARY} version #{gem_version} is not supported. Please use version >= #{MIN_VERSION}"
          end
        rescue => e
          Chore.logger.error "Could not verify #{REQUIRED_LIBRARY} version: #{e.message}" if defined?(Chore.logger)
          exit
        end
        
        Google::Cloud::PubSub.new
      end
      # Helper method to create topics and subscriptions based on the currently known list as provided by your configured Chore::Jobs
      # This is meant to be invoked from a rake task, and not directly.
      # These topics and subscriptions will be created with the default settings, which may not be ideal.
      # This is meant only as a convenience helper for testing, and not as a way to create production quality topics/subscriptions in Pub/Sub
      #
      # @param [TrueClass, FalseClass] halt_on_existing Raise an exception if the topic already exists
      #
      # @return [Array<String>]
      def self.create_queues!(halt_on_existing=false)
        raise RuntimeError.new('You must have at least one Chore Job before attempting to create Pub/Sub topics') unless Chore.prefixed_queue_names.length > 0

        if halt_on_existing
          existing = self.existing_queues
          if existing.size > 0
            raise <<-ERROR.gsub(/^\s+/, '')
            We found topics/subscriptions that already exist! Verify your queue names or prefix are setup correctly.

            The following queue names were found:
            #{existing.join("\n")}
            ERROR
          end
        end
        client = pubsub_client

        Chore.prefixed_queue_names.each do |queue_name|
          Chore.logger.info "Chore Creating Pub/Sub Topic and Subscription: #{queue_name}"
          topic_path = client.topic_path(queue_name)
          subscription_path = client.subscription_path(queue_name)
          
          # We rescue in separate blocks because in cases where topic was created
          # but the subscription was not, we still want to remove the subscription. 
          #
          # Create topic first. (Reverse on delete)
          begin
            # Create topic using topic admin
            client.topic_admin.create_topic(name: topic_path)
          rescue Google::Cloud::AlreadyExistsError => e
            Chore.logger.info "Topic already exists: #{e}"
          end

          begin
            # Create subscription using subscription admin
            client.subscription_admin.create_subscription(
              name: subscription_path,
              topic: topic_path
            )
          rescue Google::Cloud::AlreadyExistsError => e
            Chore.logger.info "Subscription already exists: #{e}"
          end
        end

        Chore.prefixed_queue_names
      end

      # Helper method to delete all known topics and subscriptions based on the list as provided by your configured Chore::Jobs
      # This is meant to be invoked from a rake task, and not directly.
      #
      # @return [Array<String>]
      def self.delete_queues!
        raise RuntimeError.new('You must have at least one Chore Job before attempting to delete Pub/Sub topics') unless Chore.prefixed_queue_names.length > 0

        client = pubsub_client
        Chore.prefixed_queue_names.each do |queue_name|
          Chore.logger.info "Chore Deleting Pub/Sub Topic and Subscription: #{queue_name}"

          # We rescue in separate blocks because in cases where subscription was removed 
          # but the topic was not, we still want to remove the topic. 
          #
          # Delete subscription first
          begin
            path = client.subscription_path(queue_name)
            client.subscription_admin.delete_subscription(subscription: path)
          rescue Google::Cloud::NotFoundError => e
            Chore.logger.error "Deleting Subscription: #{queue_name} failed because #{e}"
          end

          # Then delete topic
          begin
            path = client.topic_path(queue_name)
            client.topic_admin.delete_topic(topic: path)
          rescue Google::Cloud::NotFoundError => e
            Chore.logger.error "Deleting Topic: #{queue_name} failed because #{e}"
          end
        end

        Chore.prefixed_queue_names
      end

      # Collect a list of topics/subscriptions that already exist
      #
      # @return [Array<String>]
      def self.existing_queues
        client = pubsub_client
        Chore.prefixed_queue_names.select do |queue_name|
          begin
            client.publisher(queue_name)
            client.subscriber(queue_name)
            # if both publisher/subscriber successfully load, then assume exists
            true
          rescue Google::Cloud::NotFoundError
            # google api throws Google::Cloud::NotFoundError if topic/subscription does not exist
            false
          end
        end
      end
    end
  end
end 
