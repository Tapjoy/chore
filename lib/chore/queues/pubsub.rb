module Chore
  module Queues
    module PubSub
      class << self
        attr_accessor :project_id, :credentials
        
        # Configure PubSub settings with a block
        def configure
          yield self if block_given?
        end
      end
      
      # Creates a configured PubSub client with the given options
      # Creates a GCP Pub/Sub client using global configuration
      def self.pubsub_client
        require 'google/cloud/pubsub'
        
        # Verify compatible version
        begin
          gem_version = Gem.loaded_specs['google-cloud-pubsub']&.version
          if gem_version && gem_version < Gem::Version.new('3.0.0')
            raise "google-cloud-pubsub version #{gem_version} is not supported. Please use version >= 3.0"
          end
        rescue => e
          Chore.logger.warn "Could not verify google-cloud-pubsub version: #{e.message}" if defined?(Chore.logger)
        end
        
        if self.project_id && self.credentials
          Google::Cloud::PubSub.new(
            project_id: self.project_id,
            credentials: self.credentials
          )
        else
          Google::Cloud::PubSub.new
        end
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
          subscription_name = "#{queue_name}-sub"
          subscription_path = client.subscription_path(subscription_name)
          
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
          subscription_name = "#{queue_name}-sub"

          # We rescue in separate blocks because in cases where subscription was removed 
          # but the topic was not, we still want to remove the topic. 
          #
          # Delete subscription first
          begin
            path = client.subscription_path(subscription_name)
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
        Chore.prefixed_queue_names.select do |queue_name|
          begin
            client = pubsub_client
            client.publisher(queue_name)
            client.subscriber("#{queue_name}-sub")
            # if both publisher/subscriber successfully load, then assume exists
            true
          rescue 
            # google api throws Google::Cloud::NotFoundError if topic/subscription does not exist
            false
          end
        end
      end
    end
  end
end 
