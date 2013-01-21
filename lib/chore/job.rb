module Chore
  class Job
    attr_reader :params

    class << self
      DEFAULT_OPTIONS = { :encoder => JsonEncoder }

      def configure(opts = {})
        @options = DEFAULT_OPTIONS.merge(opts)
        raise ArgumentError.new(':queue is required') unless @options[:queue]
      end

      def options
        @options ||= configure(DEFAULT_OPTIONS)
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
      raise NotImplementedError
    end


  end #Job
end #Chore
