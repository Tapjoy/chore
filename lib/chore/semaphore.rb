module Chore
  class Semaphore
    # for demo purposes, max_leases is specified in code instead
    # of held independently in ZK
    DEFAULT_OPTIONS = {path: "/_leases", max_leases: 10}

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

      build_path!
    end

    def acquire(&block)
      if block
        Thread.new do
          wait_for_lock(&block)
        end
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
      # set up the handler if we can't immediately get a lock
      sub = @zk.register(@resource_path) do |event|
        actually_acquire_lock(&block)
      end

      # attempt to acquire a lock right now if we can
      actually_acquire_lock(&block)

      # block until we acquire a lock
      @queue.pop

    ensure
      sub.unsubscribe
    end

    def actually_acquire_lock(&block)
      if count < @max_leases
        lease_path = nil
        begin
          lease_path = create_lock!
          yield block
        ensure
          @queue.enq(:acquired)
          @zk.delete(lease_path)
        end
      end
    end

    def count
      @zk.children(@resource_path, watch: true).length
    end

    def create_lock!
      @zk.create("#{@resource_path}/", mode: :ephemeral_sequential)
    end

    def build_path!
      @zk.mkdir_p(@resource_path)
    end
  end
end

