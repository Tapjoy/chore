require 'watcher/client'
require 'watcher/publisher/statsd'

module Chore
  module Tapjoy
    def self.register_tapjoy_handlers!
      Watcher::Metric.publisher = Watcher::Publisher::Statsd.new(Chore.config.statsd[:host], Chore.config.statsd[:port])
      Watcher::Metric.default_scope = "jobs"

      after_message = Proc.new do |state|
        metric = Watcher::Metric.new("finished", attributes: { state: state })
        metric.increment
      end

      Chore.add_hook :on_failure do
        after_message.call "failed"
      end
      Chore.add_hook :on_timeout do
        after_message.call "timeout"
      end
      Chore.add_hook :on_rejected do 
        after_message.call "rejected"
      end
      Chore.add_hook :after_perform do
        after_message.call "completed"
      end

      Chore.add_hook :on_fetch do 
        metric = Watcher::Metric.new("fetch")
        metric.increment
      end
    end
  end
end
