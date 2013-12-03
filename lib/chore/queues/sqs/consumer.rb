require 'aws/sqs'
require 'chore/duplicate_detector'

AWS.eager_autoload! AWS::Core
AWS.eager_autoload! AWS::SQS

module Chore
  module Queues
    module SQS
      class Consumer < Chore::Consumer
        # Initialize the reset at on class load
        @@reset_at = Time.now

        Chore::CLI.register_option 'aws_access_key', '--aws-access-key KEY', 'Valid AWS Access Key'
        Chore::CLI.register_option 'aws_secret_key', '--aws-secret-key KEY', 'Valid AWS Secret Key'
        Chore::CLI.register_option 'dedupe_servers', '--dedupe-servers SERVERS', 'List of mememcache compatible server(s) to use for storing SQS Message Dedupe cache'
        Chore::CLI.register_option 'queue_polling_size', '--queue_polling_size NUM', Integer, 'Amount of messages to grab on each request' do |arg|
          raise ArgumentError, "Cannot specify a queue polling size greater than 10" if arg > 10
        end

        def initialize(queue_name, opts={})
          super(queue_name, opts)
        end

        def self.reset_connection!
          @@reset_at = Time.now
        end

        def consume(&handler)
          while running?
            begin
              messages = handle_messages(&handler)
              sleep 1 if messages.empty?
            rescue AWS::SQS::Errors::NonExistentQueue => e
              Chore.logger.error "You specified a queue that does not exist. You must create the queue before starting Chore. Shutting down..."
              raise Chore::TerribleMistake  
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
          msg = queue.receive_messages(:limit => sqs_polling_amount, :attributes => [:receive_count])

          messages = *msg
          messages.each do |message|
            block.call(message.handle, queue_name, message.body, message.receive_count - 1) unless duplicate_message?(message)
            Chore.run_hooks_for(:on_fetch, message.handle, message.body)
          end
          messages
        end

        def duplicate_message?(message)
          dupe_detector.found_duplicate?(message)
        end

        def dupe_detector
          @dupes ||= DuplicateDetector.new({:servers => Chore.config.dedupe_servers,
                                            :dupe_on_cache_failure => Chore.config.dupe_on_cache_failure})
        end

        def queue
          if !@sqs_last_connected || (@@reset_at && @@reset_at >= @sqs_last_connected)
            AWS::Core::Http::ConnectionPool.pools.each do |p|
              p.empty!
            end
            @sqs = nil
            @sqs_last_connected = Time.now
            @queue = nil
          end
          @queue_url ||= sqs.queues.url_for(@queue_name)
          @queue ||= sqs.queues[@queue_url]
        end

        def sqs
          @sqs ||= AWS::SQS.new(
            :access_key_id => Chore.config.aws_access_key,
            :secret_access_key => Chore.config.aws_secret_key,
            :logger => Chore.logger,
            :log_level => :debug)
        end

        def sqs_polling_amount
          Chore.config.queue_polling_size || 10
        end
      end
    end
  end
end
