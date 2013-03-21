require 'chore/util'
require 'chore/json_encoder'

module Chore
  class Worker
    include Util

    DEFAULT_OPTIONS = { :encoder => JsonEncoder }
    attr_accessor :options

    def self.start(work)
      self.new(work).start
    end

    def initialize(work=[],opts={})
      @stopping = false
      @started_at = Time.now
      @work = work
      @work = [work] unless work.kind_of?(Array)
      self.options = DEFAULT_OPTIONS.merge(opts)
    end

    def start
      @work.each do |item|
        return if @stopping
        Chore.logger.debug { "Doing: #{item.inspect}" }
        begin
          message = decode_job(item.message)
          klass = payload_class(message)
          next unless klass.run_hooks_for(:before_perform,message)
          perform_job(item,klass,message)
        rescue => e
          Chore.logger.info { "#{self.inspect}: Failed to run job #{item.inspect} with error: #{e.message}" }
          Chore.run_hooks_for(:on_failure,item.message,e)
          Chore.stats.add(:failed,:unknown)
        end
      end
    end

    def stop!
      @stopping = true
    end

    def to_json(*args)
      {
        :batch_size => (@work ? @work.length : '')
      }.to_json(*args)
    end
  protected
    def payload_class(message)
      constantize(message['class'])
    end

  private
    def perform_job(item,klass, message)
      Timeout::timeout(klass.options[:timeout]) do
        klass.perform(*message['args'])
      end
      item.consumer.complete(item.id)
      klass.run_hooks_for(:after_perform,message)
      Chore.stats.add(:completed,message['class'])
    rescue Job::RejectMessageException
      item.consumer.reject(item.id)
      klass.run_hooks_for(:on_rejected, message)
      Chore.stats.add(:rejected,message['class'])
    rescue Timeout::Error
      klass.run_hooks_for(:on_timeout, message)
      Chore.stats.add(:timeout,message['class'])
    rescue => e
      klass.run_hooks_for(:on_failure,message,e)
      Chore.stats.add(:failed,message['class'])
    end

    def decode_job(data)
      options[:encoder].decode(data)
    end
  end
end
