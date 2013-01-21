module Chore
  class Publisher
    def publish(job)
      raise NotImplementedError
    end
  protected
    def encode_job(job)
      job.options[:encoder].encode(job)
    end
  end
end
