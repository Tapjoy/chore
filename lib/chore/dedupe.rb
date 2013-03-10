module Chore
  class DuplicateDetector
    

    def initialize(servers=nil,memcached_client = nil,timeout=0)
      @memcached_options = {
        :auto_eject_hosts => false,
        :cache_lookups => false,
        :tcp_nodelay => true,
        :server_failure_limit => 5,
        :timeout => 2
      }
      # make it optional. Only required when we use it
      begin
        require 'memcached' 
      rescue LoadError => e
        Chore.logger.error "Unable to load memcached gem. It is required if duplicate \
  detection is enabled.  Install it with 'gem install memcached'."
        raise e
      end

      @timeout = timeout
      @memcached_client = (memcached_client ? memcached_client : Memcached.new(servers, @memcached_options))
    end

    def found_duplicate?(msg)
      return false unless msg && msg.respond_to?(:queue) && msg.queue
      timeout = msg.queue.visibility_timeout || @timeout
      
      begin
        @memcached_client.add(msg.id, "1",timeout)
        false
      rescue Memcached::NotStored
        true
      rescue StandardError => e
        Chore.logger.error "Error accessing duplicate cache server: #{@memcached_client.servers}. Assuming message is not a duplicate. #{e}\n#{e.backtrace * "\n"}"
        false
      end
    end
  end
end