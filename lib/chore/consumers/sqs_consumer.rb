require 'aws/sqs'
AWS.eager_autoload!

module Chore
  class SQSConsumer < Consumer
    Chore::CLI.register_option 'dedupe_servers', '--dedupe-servers SERVERS', 'List of mememcache compatible server(s) to use for storing SQS Message Dedupe cache'

    def initialize(queue_name, opts={})
      super(queue_name, opts)
      @sqs = AWS::SQS.new(
        :access_key_id => Chore.config.aws_access_key,
        :secret_access_key => Chore.config.aws_secret_key)
      @queue = @sqs.queues.named(@queue_name)
      @dupes = DuplicateDetector.new(Chore.config.dedupe_servers || nil)
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
      @queue.batch_delete([id])
    end

    private

    def handle_messages(&block)
      msg = @queue.receive_messages(:limit => 10)

      messages = *msg
      messages.each do |message|
        block.call(message.handle, message.body) unless duplicate_message?(message)
        Chore.run_hooks_for(:on_fetch, message.handle, message.body)
      end
    end

    def duplicate_message?(message)
      @dupes.found_duplicate?(message)
    end
  end
end

