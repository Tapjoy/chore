require 'watcher/client'
require 'watcher/publisher/statsd'

module Chore
  module Tapjoy
    class Monitoring
      def self.register_tapjoy_handlers!
        Watcher::Metric.publisher = Watcher::Publisher::Statsd.new(Chore.config.statsd[:host], Chore.config.statsd[:port])
        Watcher::Metric.default_scope = "stats"
        default_attributes = Chore.config.statsd[:default_attributes] || {}

        on_message = Proc.new do |name, state, queue|
          metric = Watcher::Metric.new(name, attributes: default_attributes.merge({ stat: "chore", state: state, queue: queue }))
          metric.increment
        end

        Chore.add_hook :on_failure do |message, error|
          on_message.call "finish", "failed", message['class']
        end
        Chore.add_hook :on_rejected do |message| 
          on_message.call "finish", "rejected", message['class']
        end
        Chore.add_hook :after_perform do |message|
          on_message.call "finish", "completed", message['class']
        end

        Chore.add_hook :on_fetch do |handle, body| 
          on_message.call "fetch", "fetched", body['class']
        end

        Chore.add_hook :before_perform do |message|
          on_message.call "start", "started", message['class']
        end
      end
    end
  end
end
