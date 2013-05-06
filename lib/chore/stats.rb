module Chore
  class StatEntry #:nodoc:
    attr_accessor :type, :data, :timestamp

    def initialize(type,data)
      @timestamp = Time.now.to_i
      @type, @data = type, data
    end

    def to_json(*args)
      {
        :timestamp => timestamp,
        :type => type,
        :data => data
      }.to_json(*args)
    end
  end

  class RingBuffer < Array #:nodoc:

    alias_method :array_push, :push
    alias_method :<<, :push

    def initialize(max)
      @buffer_max = max
      super()
    end

    def push(el)
      if length == @ring_size
        shift 
      end
      array_push el
    end

  end

  class Stats
    # Stats is a class to hold current real-time information about what a chore process
    # is up to. This includes things like: a list of workers and their uptime, the type 
    # and timestamp of the last +max_bucket_size+ jobs to be processed. It's what gets
    # served up on the internal stat server. Overriding <tt>to_json</tt> would change
    # the output on the stat server.

    def initialize(max_bucket_size=1000)
      @max_size = max_bucket_size
      @buckets = {}
    end

    # Add an entry to the stat list. 
    # * +stat+ should be the key of the stat to track.
    # * +type+ should be the bucket to put the stat record into, or a StatEntry instance.
    # * +data+ if type is not a StatEntry data must be provided to build a StatEntry.
    def add(stat,type=:global,data=nil)
      entry = nil
      # Allow a stat entry to come in directly
      entry = type if type.kind_of? StatEntry
      # Build an entry if given the parts
      entry = StatEntry.new(type,data) unless entry
      self[stat] << entry
    end

    # Return the data about a particular stat.
    def get(stat,type=nil)
      return self[stat] unless type
      self[stat].select {|s| s.type == type}
    end

    def [](stat) #:nodoc:
      @buckets[stat.to_sym] ||= RingBuffer.new(@max_size) #Hash.new { |h,k| h[k] = RingBuffer.new(@max_size) }
    end

    def to_json(*args)
      {
        :counts => @buckets.map {|name,v| { name => v.count}},
        :buckets => @buckets
      }.to_json(*args)
    end

  end
end
