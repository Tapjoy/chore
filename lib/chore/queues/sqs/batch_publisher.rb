require 'chore/publisher'

module Chore
  module Queues
    module SQS
      class BatchPublisher < Chore::SQS::Publisher
        @@reset_next = true

        def initialize(opts={})
          super
          @queue = []
          @timer = nil
          @running = false
          @interval = opts[:interval] || 10
        end

        def start(queue_name, interval)
          @running = true
          @timer = Thread.new do
            loop do
              if @queue.length >= 10
                empty_queue
              else
                sleep(interval)
                empty_queue
              end
            end
          end
        end

        def publish(queue_name, job)
          start(queue_name, @interval) unless @running
          @queue << {:message_body => encode_job(job)}
        end

        def empty_queue
          queue = self.queue(queue_name)
          queue.batch_send(@queue.slice!(0..9))
        end
      end
    end
  end
end
