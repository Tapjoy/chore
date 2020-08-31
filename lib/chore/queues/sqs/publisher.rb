require 'chore/publisher'

module Chore
  module Queues
    module SQS
      # SQS Publisher, for writing messages to SQS from Chore
      class Publisher < Chore::Publisher
        @@reset_next = true

        # @param [Hash] opts Publisher options
        def initialize(opts={})
          super
          @sqs_queues = {}
          @sqs_queue_urls = {}
        end

        # Publishes a message to an SQS queue
        #
        # @param [String] queue_name Name of the SQS queue
        # @param [Hash] job Job instance definition, will be encoded to JSON
        #
        # @return [struct Aws::SQS::Types::SendMessageResult]
        def publish(queue_name,job)
          queue = self.queue(queue_name)
          queue.send_message(encode_job(job))
        end

        # Sets a flag that instructs the publisher to reset the connection the next time it's used
        # TODO: We reset on every publish. Is this desirable? Seems like a performance problem.
        #
        # @return [Array<Seahorse::Client::NetHttp::ConnectionPool>]
        def self.reset_connection!
          @@reset_next = true
        end

        private

        # SQS API client object
        #
        # @return [Aws::SQS::Client]
        def sqs
          @sqs ||= AWS::SQS.new(
            :access_key_id => Chore.config.aws_access_key,
            :secret_access_key => Chore.config.aws_secret_key,
            :logger => Chore.logger,
            :log_level => :debug)
        end

        # Retrieves the SQS queue object. The method will cache the results to prevent round trips on subsequent calls
        #
        # If <tt>reset_connection!</tt> has been called, this will result in the connection being re-initialized,
        # as well as clear any cached results from prior calls
        #
        # @param [String] name Name of SQS queue
        #
        # @return [Aws::SQS::Queue]
        def queue(name)
         if @@reset_next
            AWS::Core::Http::ConnectionPool.pools.each do |p|
              p.empty!
            end
            @sqs = nil
            @@reset_next = false
            @sqs_queues = {}
          end
          @sqs_queue_urls[name] ||= self.sqs.queues.url_for(name)
          @sqs_queues[name] ||= self.sqs.queues[@sqs_queue_urls[name]]
        end
      end
    end
  end
end
