require 'chore/publisher'

module Chore
  module Queues
    module SQS
      class Publisher < Chore::Publisher
        @@reset_next = true

        def initialize(opts={})
          super
          @sqs_queues = {}
          @sqs_queue_urls = {}
        end

        def publish(queue_name,job)
          queue = self.queue(queue_name)
          queue.send_message(encode_job(job))
        end

        def self.reset_connection!
          @@reset_next = true
        end

        def sqs
          @sqs ||= AWS::SQS.new(
            :access_key_id => Chore.config.aws_access_key,
            :secret_access_key => Chore.config.aws_secret_key,
            :logger => Chore.logger,
            :log_level => :debug)
        end

        def publish(queue_name,job)
          queue = self.queue(queue_name)
          queue.send_message(encode_job(job))
        end

        def queue(name)
         if @@reset_next
            AWS::Core::Http::ConnectionPool.pools.each do |p|
              p.empty!
            end
            @sqs = nil
            @@reset_next = false
            @sqs_queues = {}
            @sqs_queue_urls = {}
          end
          @sqs_queue_urls[name] ||= self.sqs.queues.url_for(name)
          @sqs_queues[name] ||= self.sqs.queues[@sqs_queue_urls[name]]
        end
      end
    end
  end
end
