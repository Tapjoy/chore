module Chore
  class Worker
    include Util

    DEFAULT_OPTIONS = { :encoder => JsonEncoder }
    attr_accessor :options

    def self.start(messages,manager=nil,consumer=nil,args={})
      self.new(args).start(messages,manager,consumer)
    end

    def initialize(opts={})
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    def setup
      raise NotImplementedError
    end

    def start(messages,manager,consumer)
      raise NotImplementedError
    end
  private
    
    def decode_job(data)
      options[:encoder].decode(data)
    end
  end
end
