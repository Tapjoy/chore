module Chore
  class Worker
    include Hooks
    include Util

    DEFAULTS = {}

    def self.start(args={})
      self.new(args).start
    end

    def initialize(opts={})
      @options = DEFAULTS.merge(opts)
    end

    def setup
      raise NotImplementedError
    end

    def start
      raise NotImplementedError
    end
  private
    
    def decode_job(data)
      JsonEncoder.decode(data)
    end
  end
end
