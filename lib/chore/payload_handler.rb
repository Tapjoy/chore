module Chore
  class PayloadHandler
    extend Util

    def self.payload_class(message)
      constantize(message["class"])
    end

    # Takes UnitOfWork and return decoded message
    def self.decode(item)
      Encoder::JsonEncoder.decode(item.message)
    end

    def self.payload(message)
      message["args"]
    end

    # Resque/Sidekiq compatible serialization. No reason to change what works
    def self.job_hash(klass, job_params)
      # JSON only recognizes string keys, so use strings as keys in our hash for consistency in encoding/decoding
      {"class" => klass, "args" => job_params}
    end
  end
end
