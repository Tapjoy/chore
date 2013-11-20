module Chore
  # Wrapper around an OpenStruct to define configuration data
  # (TODO): Add required opts, and validate that they're set
  class Configuration < OpenStruct
    def merge_hash(hsh={})
      hsh.keys.each do |k|
        self.send("#{k.to_sym}=",hsh[k])
      end
      self
    end
  end
end