require 'watcher/client'
require 'watcher/publisher/statsd'

module Chore
  module Tapjoy
    class Monitoring
      def self.register_tapjoy_handlers!
        Watcher::Metric.publisher = Watcher::Publisher::Statsd.new(Chore.config.statsd[:host], Chore.config.statsd[:port])
        Watcher::Metric.default_scope = "jobs"

        after_message = Proc.new do |state, queue|
          metric = Watcher::Metric.new("finished", attributes: { :state => state, :queue => queue })
          metric.increment
        end

        Chore.add_hook :on_failure do |message|
          after_message.call "failed", message['class']
        end
        Chore.add_hook :on_timeout do |message|
          after_message.call "timeout", message['class']
        end
        Chore.add_hook :on_rejected do |message| 
          after_message.call "rejected", message['class']
        end
        Chore.add_hook :after_perform do |message|
          after_message.call "completed", message['class']
        end

        Chore.add_hook :on_fetch do |handle, body| 
          metric = Watcher::Metric.new("fetch")
          metric.increment
        end
      end
    end
  end
end
