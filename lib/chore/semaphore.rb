module Chore
  class Semaphore
    DEFAULT_OPTIONS = {:path => "/_leases", :max_leases => 10}

    attr_reader :max_leases
    attr_reader :path
    attr_reader :resource_name

    def initialize(resource_name, opts = {})
      opts = DEFAULT_OPTIONS.merge(opts)

      @zk = ZK.new
      @resource_name = resource_name
      @path = opts[:path]
      @resource_path = "#{@path}/#{@resource_name}"
      @max_leases = opts[:max_leases]
      @queue = Queue.new
      @subscription = nil

      build_path!
    end

    def acquire(&block)
      if block
        wait_for_lock(&block)
      else
        if count < @max_leases
          Lease.new(create_lock!, @zk)
        else
          nil
        end
      end
    end

    private

    def wait_for_lock(&block)
      # attempt to acquire a lock right now if we can
      unless actually_acquire_lock(&block)
        begin
          # set up the handler if we can't immediately get a lock
          @subscription = @zk.register(@resource_path) do |event|
            actually_acquire_lock(&block)
          end

          # block until we acquire a lock
          @queue.pop
        ensure
          @subscription.unsubscribe
        end
      end
    end

    def actually_acquire_lock(&block)
      if count < @max_leases
        @subscription.unsubscribe if @subscription
        lease_path = nil
        begin
          lease_path = create_lock!
          yield block
        ensure
          @queue.enq(:acquired)
          @zk.delete(lease_path)
          true
        end
      else
        false
      end
    end

    def count
      @zk.children(@resource_path, watch: true).length
    end

    def create_lock!
      @zk.create("#{@resource_path}/", :mode => :ephemeral_sequential)
    end

    def build_path!
      @zk.mkdir_p(@resource_path)
    end
  end
end

