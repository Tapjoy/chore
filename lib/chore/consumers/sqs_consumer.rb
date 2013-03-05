require 'aws/sqs'
require 'chore/consumer'
require 'chore/dedupe'

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

    def consume
      # this is for spec purposes, so we can test this w/out looping forever
      while loop_forever?
        msg = @queue.receive_messages(:limit => 10, :wait_time_in_seconds => 20)
        next if msg.nil? || msg.empty?
        if msg.kind_of? Array
          msg.each { |m| yield m.handle, m.body unless @dupes.found_duplicate?(msg)}
        else
          yield msg.handle, msg.body unless @dupes.found_duplicate?(msg)
        end
      end
    end

    def reject(msg)

    end

    def complete(id)
      Chore.logger.debug "Completing (deleting): #{id}"
      @queue.batch_delete([id])
    end

    private
    def loop_forever?
      # Quit looping if the fetcher is telling us that it's trying to shutdown
      true && !Chore::Fetcher.stopping?
    end
  end
end

