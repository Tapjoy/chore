module Chore
  class BatchedWorker < Worker
    # This method will perform a batching operation, where all the messages for a given
    # job class will be grouped together by that class, and handed to it in a single batch.
    # This is a special use case, only to be used when the performance benefits of
    # running multiple jobs as one makes sense.
    def start
      # First, we need to deserialize the message payloads
      @work.each {|item| item.decoded_message = options[:payload_handler].decode(item.message)}
      # Now, because a single queue could theoretically contain different job payloads,
      # we need to group the results by job type
      work_groups = @work.group_by {|item| item.klass = options[:payload_handler].payload_class(item.decoded_message)}
      # We now have a hash of JobClass => Array of payloads to run
      work_groups.each do |klass, items|
        return if @stopping
        begin
          start_batched_items(klass, items)
        rescue => e
          Chore.logger.error { "Failed to run batched-jobs for #{items.map(&:message).join("\n")} with error: #{e.message} #{e.backtrace * "\n"}" }
          items.each do |item|
            if item.current_attempt >= Chore.config.max_attempts
              Chore.run_hooks_for(:on_permanent_failure,item.queue_name,item.message,e)
              item.consumer.complete(item.id)
            else
              Chore.run_hooks_for(:on_failure,item.message,e)
            end
          end
        end
      end
    end

    def start_batched_items(klass, items)
      items.each {|item| return unless item.klass.run_hooks_for(:before_perform,item.message)}
      logged_batch_payload = items.map(&:message).join("\n")
      begin
        Chore.logger.info { "Running job #{klass} with params #{logged_batch_payload}"}
        perform_batch_job(klass,items.map(&:decoded_message))
        items.each do |item|
          item.consumer.complete(item.id)
          klass.run_hooks_for(:after_perform, item.decoded_message)
        end
        Chore.logger.info { "Finished job #{klass} with params #{logged_batch_payload}"}
      rescue Job::RejectMessageException
        Chore.logger.error { "Failed to run job for #{logged_batch_payload}  with error: Job raised a RejectMessageException" }
        items.each do |item|
          item.consumer.reject(item.id)
          klass.run_hooks_for(:on_rejected, item.decoded_message)
        end
      rescue => e
        items.each do |item|
          if klass.has_backoff?
            attempt_to_delay(item, item.decoded_message, klass)
          else
            handle_failure(item, item.decoded_message, klass, e)
          end
        end
      end
    end

    def perform_batch_job(klass, messages)
      klass.perform_batch(messages.flat_map {|m|options[:payload_handler].payload(m)})
    end
  end
end
