require 'chore/publisher'
require 'chore/queues/sqs/batch_sending_pool'
require 'thread'

module Chore
  module Queues
    module SQS
      class Publisher < Chore::Publisher
        @@reset_next       = true
        @@running          = false
        @@stopping         = false
        @@timer            = nil
        @@thread_pool      = nil
        @@messages         = {}
        @@threadpool_mutex = Mutex.new

        # AWS has a hard limit on how many messages can be batch published.
        AWS_BATCH_LIMIT = 10

        # we have tested with a pool size of 5 and appear to get good performance out of it
        # in a QE environment. This default is driven by testing with event-service, so it may
        # not be the correct default for you.
        DEFAULT_BATCH_SIZE = 5

        def initialize(opts={})
          super
          Chore.logger.debug "#{Chore.config}"
          @sqs_queues = {}
          @sqs_queue_urls = {}
          # default to non-batched message sending
          @send_in_batches = Chore.config.send_in_batches || false
          if @send_in_batches
            # we have tested with a pool size of 5 and appear to get good performance out of it
            # in a QE environment. This default is driven by testing with event-service, so it may
            # not be the correct default for you.
            pool_size = (Chore.config.messaging_pool_size || DEFAULT_BATCH_SIZE).to_i
            @@threadpool_mutex.synchronize do
              @@thread_pool ||= BatchSendingPool.new(pool_size)
            end
          end
        end

        def publish(queue_name,job)
          # If we are shutting down, stop modifying the local @@messages queues. Instead
          # directly publish to the SQS queue.
          if @send_in_batches && !@@stopping
            @@threadpool_mutex.synchronize do
              @@messages[queue_name] ||= Queue.new
            end
            self.class.spawn_timer unless @@running
            batch_enqueue(queue_name, job)
          else
            queue = self.queue(queue_name)
            queue.send_message(encode_job(job))
          end
        end

        def batch_enqueue(queue_name, job)
          @@messages[queue_name] << {:message_body => encode_job(job)}
        end

        def self.spawn_timer
          @@running = true
          @@timer = Thread.new do
            loop do
              @@threadpool_mutex.synchronize do
                @@messages.keys.each do |queue_name|
                  # iterate through the queues and send batches to the thread pool for processing
                  pass_batch_to_thread_pool(queue_name)
                end
              end
              # so, something strange happens if we don't suggest to ruby that it goes on to the next
              # thread. We were unable to determine the root cause for it, but suspect that this loop
              # is run so tight, that it doesn't immediately pass off to the next thread and causes
              # our response times to spike. This Thread.pass is *marginally* better than the 
              # sleep 0.00001 that we had here previously.
              Thread.pass
            end
          end
          Chore.logger.info "sqs batch publishing timer thread started"
        end

        def self.stop_timer
          @@stopping = true
          @@timer.join if @@timer
          @@timer = nil
          @@running = false
          Chore.logger.info "sqs batch publishing timer thread stopped"

          @@messages.each do |queue_name, jobs|
            until @@messages[queue_name].empty?
              pass_batch_to_thread_pool(queue_name)
            end
          end
          @@thread_pool.shutdown
          Chore.logger.info "sqs batch publishing thread pool shutting down"
          @@stopping = false
          Chore.logger.info "sqs batch publisher shut down"
        end

        def self.pass_batch_to_thread_pool(queue_name)
          msgs = @@messages[queue_name]
          batch_size = msgs.length > AWS_BATCH_LIMIT ? AWS_BATCH_LIMIT : msgs.length
          # don't enqueue an empty batch
          return if batch_size == 0
          batch = []
          batch_size.times do |i| 
            begin
              # we don't want this thread to go to sleep if there are no messages available
              msg = msgs.pop(true)
              # So, AWS requires each message in the array to have an id. It should be created 
              # when the message is processed by the aws-sdk gem's batch_send method, but I was 
              # getting errors that the id wasn't being set without having this manually configured here. 
              msg[:id] = i
              batch << msg
            rescue ThreadError
              # this means the queue was empty when we tried to #pop from it
            end
          end
          Chore.logger.info "Sending a batch of #{batch.length} messages to sqs publisher threadpool"


          @@thread_pool.process do
            begin
              Chore.logger.debug "processing job #{batch.inspect} with sqs batching threadpool"
              Chore::Queues::SQS::Publisher.batch_send(queue_name, batch)
            rescue AWS::SQS::Errors::BatchSendError => e
              # if a message fails a batch send, add it back into the list of messages to try later
              Chore.logger.error "failed messages: #{e.failures.map(&:inspect)}. Rescheduling."
              e.failures.each do |f|
                @@messages[queue_name] << f
              end
            rescue => e
              Chore.logger.error "failed with #{e.inspect} \n #{e.backtrace}"
            end
          end
        end

        def self.batch_send(queue_name, batch)
          Chore.logger.info "Sending batch of #{batch.length} messages to SQS"
          queue = self.new.queue(queue_name)
          queue.batch_send(*batch)
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
