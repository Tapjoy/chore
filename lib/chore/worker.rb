require 'chore/util'
require 'chore/json_encoder'

module Chore
  class Worker
    include Util

    DEFAULT_OPTIONS = { :encoder => JsonEncoder }
    attr_accessor :options

    def self.start(work,args={})
      self.new(args).start(work)
    end

    def initialize(opts={})
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    def start(work)
      work = [work] unless work.kind_of?(Array)
      work.each do |item|
        puts "Doing: #{item.inspect}"
        begin
          message = decode_job(item.message)
          klass = constantize(message['class'])
          begin
            break unless klass.run_hooks_for(:before_perform,*message['args'])
            klass.perform(*message['args'])
            item.consumer.complete(item.id)
            klass.run_hooks_for(:after_perform,*message['args'])
          rescue Job::RejectMessageException
            item.consumer.reject(item.id)
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
