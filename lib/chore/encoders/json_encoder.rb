require 'multi_json'

module Chore
  module Encoder
    # Json encoding for serializing jobs. 
    module JsonEncoder
      class << self
        # Encodes the +job+ into JSON using the standard ruby JSON parsing library
        def encode(job)
          MultiJson.dump(job.to_hash)
        end

        # Decodes the +job+ from JSON into a ruby Hash using the standard ruby JSON parsing library
        def decode(job)
          MultiJson.load(job)
        end
      end
    end
  end
end
