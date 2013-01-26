module Chore
  class Publisher
    include Hooks

    def publish(job)
      raise NotImplementedError
    end
  protected

    def encode_job(job)
      #job.options[:encoder].encode(job)
      JsonEncoder.encode(job)
    end

    def call_publish_hooks(job)
      run_hooks_for(:before_publish,job[:params])
    end
  end
end
