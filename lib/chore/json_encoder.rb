module Chore
  module JsonEncoder
    class << self
      def encode(job)
        JSON.encode(job.to_hash)
      end

      def decode(job)
        JSON.decode(job)
      end
    end
  end
end
