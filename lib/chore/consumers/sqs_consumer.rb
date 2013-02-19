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
        msg = @queue.receive_message
        yield msg if block_given?
      end
    end

    def reject(msg)

    end

    def complete(msg)

    end

    private
    def loop_forever?
      true
    end
  end
end

