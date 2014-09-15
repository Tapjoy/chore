module Chore
  module Queues
    module SQS
      # Helper method to create queues based on the currently known list as provided by your configured Chore::Jobs
      # This is meant to be invoked from a rake task, and not directly.
      # These queues will be created with the default settings, which may not be ideal. 
      # This is meant only as a convenience helper for testing, and not as a way to create production quality queues in SQS
      def self.create_queues!
        raise 'You must have atleast one Chore Job configured and loaded before attempting to create queues' unless Chore.prefixed_queue_names.length > 0
        #This will raise an exception if AWS has not been configured by the project making use of Chore
        sqs_queues = AWS::SQS.new.queues
        Chore.prefixed_queue_names.each do |queue_name|
          Chore.logger.info "Chore Creating Queue: #{queue_name}"
          begin
            sqs_queues.create(queue_name)
          rescue AWS::SQS::Errors::QueueAlreadyExists
            Chore.logger.info "exists with different config"
          end
        end
        Chore.prefixed_queue_names
      end

      # Helper method to delete all known queues based on the list as provided by your configured Chore::Jobs
      # This is meant to be invoked from a rake task, and not directly.
      def self.delete_queues!
        raise 'You must have atleast one Chore Job configured and loaded before attempting to create queues' unless Chore.prefixed_queue_names.length > 0
        #This will raise an exception if AWS has not been configured by the project making use of Chore
        sqs_queues = AWS::SQS.new.queues
        Chore.prefixed_queue_names.each do |queue_name|
          Chore.logger.info "Chore Deleting Queue: #{queue_name}"
          url = sqs_queues.url_for(queue_name)
          sqs_queues[url].delete
        end
        Chore.prefixed_queue_names
      end
    end
  end
end
