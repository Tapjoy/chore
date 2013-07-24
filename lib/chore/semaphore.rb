module Chore
  class Semaphore
    DEFAULT_OPTIONS = {:path => "/_leases"}

    attr_reader :max_leases
    attr_reader :path
    attr_reader :resource_name

    def initialize(resource_name, zk, opts = {})
      opts = DEFAULT_OPTIONS.merge(opts)

      @zk = zk
      @resource_name = resource_name
      @path = opts[:path]
      @resource_path = "#{@path}/#{@resource_name}"
      @queue = Queue.new
      @subscription = nil

      build_path!
    end

    def acquire(&block)
      if block
        wait_for_lease(&block)
      else
        if available?
          Lease.new(create_lease!, @zk)
        else
          nil
        end
      end
    end
    
    def available?
      count < max_leases
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

          set_watch

          # block until we acquire a lock
          # see the rdoc for Queue (it blocks)
          @queue.pop
        ensure
          @subscription.unsubscribe if @subscription
        end
      end
    end

    def actually_acquire_lease(&block)
      if available?
        # we need to unsubscribe before we create the lease
        # otherwise we would fire the handler when we create it
        @subscription.unsubscribe if @subscription
        unset_watch
        lease_path = nil
        begin
          lease_path = create_lease!
          Chore.logger.debug "Acquired lease at #{lease_path}"
          yield block
          true
        ensure
          @queue.enq(:acquired) if @subscription
          @zk.delete(lease_path)
          Chore.logger.debug "Releasing lease at #{lease_path}"
        end
      else
        false
      end
    end

    def count
      @zk.stat(@resource_path).num_children
    end

    def set_watch
      @zk.children(@resource_path, :watch => true)
    end

    def unset_watch
      @zk.children(@resource_path, :watch => false)
    end

    def create_lease!
      @zk.create("#{@resource_path}/", :mode => :ephemeral_sequential)
    end

    def build_path!
      @zk.mkdir_p(@resource_path)
    end

    def max_leases
      data, _stat = @zk.get("/config/#{@resource_name}/max_leases")
      data.to_i
    end
  end
end

