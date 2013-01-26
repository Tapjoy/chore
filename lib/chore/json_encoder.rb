require 'json'

module Chore
  module JsonEncoder
    class << self
      def encode(job)
        JSON.generate(job.to_hash)
      end

      def decode(job)
        JSON.parse(job)
      end
    end
  end
end
