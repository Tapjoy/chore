module Chore
  class StatEntry
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

  class RingBuffer < Array

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

    def initialize(max_bucket_size=1000)
      @max_size = max_bucket_size
      @buckets = {}
    end

    def add(stat,type=:global,data=nil)
      entry = nil
      # Allow a stat entry to come in directly
      entry = type if type.kind_of? StatEntry
      # Build an entry if given the parts
      entry = StatEntry.new(type,data) unless entry
      self[stat] << entry
    end

    def get(stat,type=nil)
      return self[stat] unless type
      self[stat].select {|s| s.type == type}
    end

    def [](stat)
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
