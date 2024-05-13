module Chore
  class DuplicateDetector #:nodoc:

    def initialize(opts={})
      @timeouts              = {}
      @dupe_on_cache_failure = opts.fetch(:dupe_on_cache_failure) { false }
      @timeout               = opts.fetch(:timeout) { 0 }
      @timeout_offset        = opts.fetch(:timeout_offset) { 10 } # Default 10 seconds. Observed race condition timing (2s) with a 5x buffer.
      @dedupe_handler        = opts.fetch(:handler) do
        require 'dalli'
        client = Dalli::Client.new(opts.fetch(:servers) { nil }, {
          :auto_eject_hosts    => false,
          :cache_lookups       => false,
          :tcp_nodelay         => true,
          :socket_max_failures => 5,
          :socket_timeout      => 2
        })

        client.method(:add)
      end
    end

    # Checks the message against the configured dedupe server to see if the message is unique or not
    # Unique messages will return false
    # Duplicated messages will return true
    def found_duplicate?(msg_data)
      return false unless msg_data && msg_data[:queue]

      timeout = queue_timeout_with_offset(msg_data)

      begin
        !@dedupe_handler.call(msg_data[:id], "1", timeout)
      rescue StandardError => e
        if @dupe_on_cache_failure
          Chore.logger.error "Error accessing duplicate cache server. Assuming message is a duplicate. #{e}\n#{e.backtrace * "\n"}"
          true
        else
          Chore.logger.error "Error accessing duplicate cache server. Assuming message is not a duplicate. #{e}\n#{e.backtrace * "\n"}"
          false
        end
      end
    end

    # Retrieves the timeout for the given queue. The timeout is the window of time in seconds that
    # we would consider the message to be non-unique, before we consider it dead in the water
    # After that timeout, we would consider the next copy of the message received to be unique, and process it.
    def queue_timeout(msg_data)
      @timeouts[msg_data[:queue]] ||= msg_data[:visibility_timeout] || @timeout
    end

    # Retrieves the timeout for the given queue, minus some offsets
    # to allow msgs in the dedupe cache to fully expire before the same msg is processed again.
    def queue_timeout_with_offset(msg_data)
      queue_timeout = self.queue_timeout(msg_data)
      received_timestamp_offset = get_received_timestamp_offset(msg_data[:received_timestamp])

      queue_timeout - received_timestamp_offset - @timeout_offset
    end

    # The time difference between when a message is Consumed and when it is Worked on
    def get_received_timestamp_offset(received_timestamp)
      (Time.now - received_timestamp).to_i
    end

  end
end
