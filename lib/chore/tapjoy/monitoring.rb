require 'watcher/client'
require 'watcher/publisher/statsd'

Watcher::Metric.publisher = Watcher::Publisher::Statsd.new
Watcher::Metric.default_scope = "jobs"

%w{ finished failed timeout }.each do |state|
  Chore.add_hook :"after_perform_#{state}" do
    metric = Watcher::Metric.new("finished", attributes: { state: state })
    metric.increment
  end
end

Chore.add_hook :on_fetch_tell_monitoring do 
  metric = Watcher::Metric.new("fetch")
  metric.increment
end
