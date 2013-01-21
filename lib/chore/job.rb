module Chore
  class Job
    attr_reader :params

    class << self
      DEFAULT_OPTIONS = { :encoder => JsonEncoder }
      REQUIRED_OPTIONS = [:queue,:publisher]

      def configure(opts = {})
        @options = (@options || DEFAULT_OPTIONS).merge(opts)
        REQUIRED_OPTIONS.each do |k|
          raise ArgumentError.new(":#{k} is required") unless @options[k]
        end
      end

      def options
        @options ||= configure
      end

      def perform(*args)
        self.new(*args).perform
      end

      def publish(*args)
        self.new(*args).publish
      end
    end

    def initialize(*args)
      @params = args
    end

    def to_hash(opts = {})
      {:job => self.class.to_s, :params => params}.merge(opts)
    end

    def setup
    end

    def perform
      raise NotImplementedError
    end

    def publish
      @publisher ||= self.options[:publisher].new
      @publisher.publish(self)
    end

  end #Job
end #Chore
