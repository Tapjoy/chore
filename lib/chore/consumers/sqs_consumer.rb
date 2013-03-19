require 'aws/sqs'

module Chore
  class SQSConsumer < Consumer

    def initialize(queue_name, opts={})
      super(queue_name, opts)
      @sqs = AWS::SQS.new(
        :access_key_id => Chore.config.aws_access_key,
        :secret_access_key => Chore.config.aws_secret_key)
      @queue = @sqs.queues.named(@queue_name)
      @dupes = DuplicateDetector.new(Chore.config.dedupe_servers || nil)
    end

    def consume(&handler)
      # this is for spec purposes, so we can test this w/out looping forever
      while running?
        begin
          msg = @queue.receive_messages(:limit => 10)
          next if msg.nil? || msg.empty?

          handle_messages(*msg, &handler)
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

    def handle_messages(*messages, &block)
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

