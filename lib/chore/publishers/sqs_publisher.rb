module Chore
  class SQSPublisher < Publisher

    def initialize(opts={})
      super
      @sqs = AWS::SQS.new(
          :access_key_id => Chore.config.aws_access_key,
          :secret_access_key => Chore.config.aws_secret_key)
    end

    def self.publish(queue_name,job)
      self.new.publish(queue_name,job)
    end

    def publish(queue_name,job)
      queue = ensure_queue! queue_name
      queue.send_message(encode_job(job))
    end

    def ensure_queue!(name)
      @sqs.queues.create(name)
    end
  end
end
