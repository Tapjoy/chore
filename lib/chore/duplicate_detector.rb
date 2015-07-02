module Chore
  class DuplicateDetector #:nodoc:

    def initialize(opts={})
      # Make it optional. Only required when we use it.
      begin
        require 'dalli'
      rescue LoadError => e
        Chore.logger.error "Unable to load dalli gem. It is required if duplicate \
  detection is enabled.  Install it with 'gem install dalli'."
        raise e
      end

      memcached_options = {
        :auto_eject_hosts    => false,
        :cache_lookups       => false,
        :tcp_nodelay         => true,
        :socket_max_failures => 5,
        :socket_timeout      => 2
      }

      @timeouts              = {}
      @dupe_on_cache_failure = opts.fetch(:dupe_on_cache_failure) { false }
      @timeout               = opts.fetch(:timeout) { 0 }
      @servers               = opts.fetch(:servers) { nil }
      @memcached_client      = opts.fetch(:memcached_client) { Dalli::Client.new(@servers, memcached_options) }
    end

    # Checks the message against the configured dedupe server to see if the message is unique or not
    # Unique messages will return false
    # Duplicated messages will return true
    def found_duplicate?(msg_data)
      return false unless msg_data && msg_data[:queue]
      timeout = self.queue_timeout(msg_data)
      begin
        !@memcached_client.add(msg_data[:id], "1",timeout)
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

  end
end
