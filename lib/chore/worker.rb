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
      @stopping = false
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    def start(work)
      @work = work
      @work = [work] unless work.kind_of?(Array)
      @work.each do |item|
        return if @stopping
        Chore.logger.debug { "Doing: #{item.inspect}" }
        begin
          message = decode_job(item.message)
          klass = payload_class(message)
          begin
            next unless klass.run_hooks_for(:before_perform,*message['args'])
            klass.perform(*message['args'])
            item.consumer.complete(item.id)
            klass.run_hooks_for(:after_perform,*message['args'])
            Chore.stats.add(:completed,message['class'])
          rescue Job::RejectMessageException
            item.consumer.reject(item.id)
            Chore.stats.add(:rejected,message['class'])
          rescue => e
            klass.run_hooks_for(:on_failure,*message['args'])
            Chore.run_hooks_for(:on_failure,message,e)
            Chore.stats.add(:failed,message['class'])
          end
        end
      end
    end

    def stop!
      @stopping = true
    end

    def to_json(*args)
      {
        :batch_size => @work.count
      }.to_json(*args)
    end
  protected
    def payload_class(message)
      constantize(message['class'])
    end

  private
    
    def decode_job(data)
      options[:encoder].decode(data)
    end
  end
end
