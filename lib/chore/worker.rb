module Chore
  class Worker
    include Util

    DEFAULT_OPTIONS = { :encoder => JsonEncoder }
    attr_accessor :options

    def self.start(messages,manager=nil,consumer=nil,args={})
      self.new(args).start(messages,manager,consumer)
    end

    def initialize(opts={})
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    def start(messages,manager,consumer)
      messages.each do |message|
        begin
          message = decode_job(message)
          klass = constantize(message['class'])
          begin
            break unless klass.run_hooks_for(:before_perform,*message['args'])
            klass.perform(*message['args'])
            consumer.complete
            klass.run_hooks_for(:after_perform,*message['args'])
          rescue Job::RejectMessageException => e
            consumer.reject
          rescue
            klass.run_hooks_for(:on_failure,*message['args'])
          end
        end
      end
    end
  private
    
    def decode_job(data)
      options[:encoder].decode(data)
    end
  end
end
