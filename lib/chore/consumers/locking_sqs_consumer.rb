require 'zk'

module Chore
  class LockingSQSConsumer < SQSConsumer
    Chore::CLI::register_option 'zookeeper_hosts', '--zookeeper-hosts', 'Comma separated list of Zookeeper hosts in the form of host:port'

    def initialize(queue_name, opts={})
      super(queue_name, opts)
      @@zk ||= ZK.new(Chore.config.zookeeper_hosts)
      @last_updated = Time.now - 120 # 2 minutes
      @requires = false
    end

    def consume(&handler)
      while running?
        begin
          if requires_lock?
            semaphore = Semaphore.new(@queue_name, @@zk)
            semaphore.acquire do
              msg = @queue.receive_messages(:limit => 10)
              next if msg.nil? || msg.empty?

              handle_messages(*msg, &handler)
            end
          else
            msg = @queue.receive_messages(:limit => 10)
            next if msg.nil? || msg.empty?

            handle_messages(*msg, &handler)
          end
        rescue => e
          Chore.logger.error { "SQSConsumer#Consume: #{e.inspect}" }
        end
      end
    ensure
      @@zk.close!
    end

    private

    def requires_lock?
      if Time.now > @last_updated + 120
        data, _stat = @@zk.get("/config/#{@queue_name}/max_leases")
        @requires = data.to_i > 0
        @last_updated = Time.now
      end
      @requires
    end
  end
end
