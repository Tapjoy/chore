require 'aws/sqs'
AWS.config(
  :access_key_id => ENV['AWS_ACCESS_KEY'],
  :secret_access_key => ENV['AWS_SECRET_KEY'])

module Chore
  class SQSConsumer < Consumer
    SQS = AWS::SQS.new
  
    def initialize(queue_name, opts={})
      super(queue_name, opts)
      @queue = SQS.queues.named(@queue_name)
    end

    def consume
      # this is for spec purposes, so we can test this w/out looping forever
      while loop_forever?
        msg = @queue.receive_messages(:limit => 10, :wait_time_in_seconds => 20)
        next if msg.nil? || msg.empty?
        if msg.kind_of? Array
          msg.each { |m| yield m.handle, m.body }
        else
          yield msg.handle, msg.body
        end
      end
    end

    def reject(msg)

    end

    def complete(id)
      puts "Completing (deleting): #{id}"
      @queue.batch_delete([id])
    end

    private
    def loop_forever?
      true
    end
  end
end

