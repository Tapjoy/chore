require 'aws/sqs'
require 'chore/duplicate_detector'

AWS.eager_autoload!

module Chore
  module Queues
    module SQS
      class Consumer < Chore::Consumer
        Chore::CLI.register_option 'dedupe_servers', '--dedupe-servers SERVERS', 'List of mememcache compatible server(s) to use for storing SQS Message Dedupe cache'

        def initialize(queue_name, opts={})
          super(queue_name, opts)
        end

        def self.reset_connection!
          @@reset_at = Time.now
        end

        def consume(&handler)
          while running?
            begin
              handle_messages(&handler)
            rescue => e
              Chore.logger.error { "SQSConsumer#Consume: #{e.inspect}" }
            end
          end
        end

        def reject(id)

        end

        def complete(id)
          Chore.logger.debug "Completing (deleting): #{id}"
          queue.batch_delete([id])
        end

        private

        def handle_messages(&block)
          msg = queue.receive_messages(:limit => 10)

          messages = *msg
          messages.each do |message|
            block.call(message.handle, message.body) unless duplicate_message?(message)
            Chore.run_hooks_for(:on_fetch, message.handle, message.body)
          end
        end

        def duplicate_message?(message)
          dupe_detector.found_duplicate?(message)
        end

        def dupe_detector
          @dupes ||= DuplicateDetector.new(Chore.config.dedupe_servers || nil)
        end

        def queue
          @queue ||= sqs.queues.named(@queue_name)
        end

        def sqs
          if !@sqs_last_connected || (@@reset_at && @@reset_at >= @sqs_last_connected)
            @sqs = AWS::SQS.new(
              :access_key_id => Chore.config.aws_access_key,
              :secret_access_key => Chore.config.aws_secret_key)
            @sqs_last_connected = Time.now
            @queue = nil
          end
          @sqs
        end

      end
    end
  end
end

