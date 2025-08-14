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
          if gem_version && gem_version < Gem::Version.new('2.23.0')
            raise "google-cloud-pubsub version #{gem_version} is not supported. Please use version ~> 2.23"
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

        Chore.prefixed_queue_names.each do |queue_name|
          Chore.logger.info "Chore Creating Pub/Sub Topic and Subscription: #{queue_name}"
          topic = pubsub_client.create_topic(queue_name)
          subscription_name = "#{queue_name}-sub"
          
          begin
            topic.create_subscription(subscription_name)
          rescue Google::Cloud::AlreadyExistsError
            Chore.logger.info "Subscription #{subscription_name} already exists"
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

        Chore.prefixed_queue_names.each do |queue_name|
          begin
            Chore.logger.info "Chore Deleting Pub/Sub Topic and Subscription: #{queue_name}"
            subscription_name = "#{queue_name}-sub"
            
            # Delete subscription first
            subscription = pubsub_client.subscription(subscription_name)
            subscription.delete if subscription.exists?
            
            # Then delete topic
            topic = pubsub_client.topic(queue_name)
            topic.delete if topic.exists?
          rescue => e
            # This could fail for a few reasons - log out why it failed, then continue on
            Chore.logger.error "Deleting Topic/Subscription: #{queue_name} failed because #{e}"
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
            topic = pubsub_client.topic(queue_name)
            subscription = pubsub_client.subscription("#{queue_name}-sub")
            topic.exists? || subscription.exists?
          rescue => e
            false
          end
        end
      end
    end
  end
end 