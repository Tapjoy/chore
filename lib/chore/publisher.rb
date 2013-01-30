module Chore
  class Publisher
    include Hooks
    DEFAULT_OPTIONS = { :encoder => JsonEncoder }

    attr_accessor :options

    def initialize(opts={})
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    def publish(job)
      raise NotImplementedError
    end
  protected

    def encode_job(job)
      options[:encoder].encode(job)
    end

    def call_publish_hooks(job)
      run_hooks_for(:before_publish,job[:params])
    end
  end
end
