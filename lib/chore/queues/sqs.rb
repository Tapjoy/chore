module Chore
  module Queues
    module SQS
      def self.sqs_client
        Aws::SQS::Client.new(
          logger: Chore.logger,
          log_level: Chore.log_level_to_sym,
          instance_profile_credentials_timeout: 5, # default: 1
          instance_profile_credentials_retries: 5, # default: 0
        )
      end

      # Helper method to create queues based on the currently known list as provided by your configured Chore::Jobs
      # This is meant to be invoked from a rake task, and not directly.
      # These queues will be created with the default settings, which may not be ideal.
      # This is meant only as a convenience helper for testing, and not as a way to create production quality queues in SQS
      #
      # @param [TrueClass, FalseClass] halt_on_existing Raise an exception if the queue already exists
      #
      # @return [Array<String>]
      def self.create_queues!(halt_on_existing=false)
        raise 'You must have atleast one Chore Job configured and loaded before attempting to create queues' unless Chore.prefixed_queue_names.length > 0

        if halt_on_existing
          existing = self.existing_queues
          if existing.size > 0
            raise <<-ERROR.gsub(/^\s+/, '')
            We found queues that already exist! Verify your queue names or prefix are setup correctly.

            The following queue names were found:
            #{existing.join("\n")}
            ERROR
          end
        end

        Chore.prefixed_queue_names.each do |queue_name|
          Chore.logger.info "Chore Creating Queue: #{queue_name}"
          begin
            sqs_client.create_queue(queue_name: queue_name)
          rescue Aws::SQS::Errors::QueueAlreadyExists
            Chore.logger.info "exists with different config"
          end
        end

        Chore.prefixed_queue_names
      end

      # Helper method to delete all known queues based on the list as provided by your configured Chore::Jobs
      # This is meant to be invoked from a rake task, and not directly.
      #
      # @return [Array<String>]

      def self.delete_queues!
        raise 'You must have atleast one Chore Job configured and loaded before attempting to create queues' unless Chore.prefixed_queue_names.length > 0

        Chore.prefixed_queue_names.each do |queue_name|
          begin
            Chore.logger.info "Chore Deleting Queue: #{queue_name}"
            url = sqs_client.get_queue_url(queue_name: queue_name).queue_url
            sqs_client.delete_queue(queue_url: url)
          rescue => e
            # This could fail for a few reasons - log out why it failed, then continue on
            Chore.logger.error "Deleting Queue: #{queue_name} failed because #{e}"
          end
        end

        Chore.prefixed_queue_names
      end

      # Collect a list of queues that already exist
      #
      # @return [Array<String>]
      def self.existing_queues
        Chore.prefixed_queue_names.select do |queue_name|
          # If the NonExistentQueue exception is raised we do not care about that queue name.
          begin
            sqs_client.get_queue_url(queue_name: queue_name)
            true
          rescue Aws::SQS::Errors::NonExistentQueue
            false
          end
        end
      end
    end
  end
end
