module Chore
  class Lease
    attr_reader :path

    def initialize(path, zookeeper)
      @path = path
      @zk = zookeeper
    end

    def release
      @zk.delete(path)
    end
  end
end
