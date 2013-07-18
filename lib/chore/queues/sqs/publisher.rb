require 'chore/publisher'

module Chore
  module Queues
    module SQS
      class Publisher < Chore::Publisher

        def initialize(opts={})
          super
          @sqs = AWS::SQS.new(
              :access_key_id => Chore.config.aws_access_key,
              :secret_access_key => Chore.config.aws_secret_key)
          @sqs_queues = {}
        end

        def publish(queue_name,job)
          queue = self.queue(queue_name)
          queue.send_message(encode_job(job))
        end

        def queue(name)
          @sqs_queues[name] ||= @sqs.queues.named(name)
        end
      end
    end
  end
end
