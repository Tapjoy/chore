require 'zk'

module Chore
  class LockingSQSConsumer < SQSConsumer
    Chore::CLI::register_option 'zookeeper_hosts', '--zookeeper-hosts', 'Comma separated list of Zookeeper hosts in the form of host:port'

    def initialize(queue_name, opts={})
      super(queue_name, opts)
      @zk = ZK.new(Chore.config.zookeeper_hosts)
    end

    def consume(&handler)
      while running?
        begin
          if requires_lock?
            semaphore = Semaphore.new(@queue_name, @zk)
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
    end

    private

    def requires_lock?
      data, _stat = @zk.get("/config/#{@queue_name}/max_leases")
      data.to_i > 0
    end
  end
end
