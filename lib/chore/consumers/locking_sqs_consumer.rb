require 'zk'
require 'chore/lease'
require 'chore/semaphore'
require 'chore/consumers/sqs_consumer'

module Chore
  class LockingSQSConsumer < SQSConsumer
    Chore::CLI::register_option 'zookeeper_hosts', '--zookeeper-hosts HOSTS', 'Comma separated list of Zookeeper hosts in the form of host:port'
    UPDATE_TIMEOUT = (2 * 60) # 2 minutes

    def initialize(queue_name, opts={})
      super(queue_name, opts)
      @@zk ||= ZK.new(Chore.config.zookeeper_hosts)
      @last_updated = Time.now - UPDATE_TIMEOUT
      @max_leases = 0
    end

    def consume(&handler)
      while running?
        begin
          if enabled?
            if requires_lock?
              semaphore = Semaphore.new(@queue_name, @@zk)
              semaphore.acquire do
                handle_messages(&handler)
              end
            else
              handle_messages(&handler)
            end
          end
        rescue => e
          Chore.logger.error { "LockingSQSConsumer#Consume: #{e.inspect}" }
        end
      end
    ensure
      @@zk.close!
    end

    private

    def requires_lock?
      max_leases > 0
    end

    def enabled?
      max_leases != -1
    end

    def max_leases
      if Time.now > @last_updated + UPDATE_TIMEOUT
        data, _stat = @@zk.get("/config/#{@queue_name}/max_leases")
        @max_leases = data.to_i
        @last_updated = Time.now
      end
      @max_leases
    end
  end
end
