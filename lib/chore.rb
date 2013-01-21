module Chore
  VERSION = '0.0.1'

  autoload :JsonEncoder,    "chore/json_encoder"
  autoload :Job,            "chore/job"
#  autoload :Worker,         "chore/worker"
 
  class Worker
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

  end
end
