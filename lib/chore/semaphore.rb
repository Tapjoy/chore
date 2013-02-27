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
        wait_for_lease(&block)
      else
        if count < @max_leases
          Lease.new(create_lease!, @zk)
        else
          nil
        end
      end
    end

    private

    def wait_for_lease(&block)
      # attempt to acquire a lock right now if we can
      unless actually_acquire_lease(&block)
        begin
          # set up the handler if we can't immediately get a lease
          @subscription = @zk.register(@resource_path) do |event|
            actually_acquire_lease(&block)
          end

          # block until we acquire a lock
          # see the rdoc for Queue (it blocks)
          @queue.pop
        ensure
          @subscription.unsubscribe if @subscription
        end
      end
    end

    def actually_acquire_lease(&block)
      if count < @max_leases
        # we need to unsubscribe before we create the lease
        # otherwise we would fire the handler when we create it
        @subscription.unsubscribe if @subscription
        lease_path = nil
        begin
          lease_path = create_lease!
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
      # gotta set that watch every time or our handler
      # might not fire which would be such a bummer man
      # yeah whoa
      @zk.children(@resource_path, watch: true).length
    end

    def create_lease!
      @zk.create("#{@resource_path}/", :mode => :ephemeral_sequential)
    end

    def build_path!
      @zk.mkdir_p(@resource_path)
    end
  end
end

