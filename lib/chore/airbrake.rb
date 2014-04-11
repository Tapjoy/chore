gem 'airbrake', '>= 3.1.3'
require 'airbrake'
require 'chore'

# Require this file to enable airbraking all exceptions thrown from jobs
# use Chore.config.airbrake to set airbrake options for sending notifications

unless Airbrake.configuration.api_key
  raise "Chore airbrake support requires that Airbrake is already configured but the API key is not currently set"
end

Airbrake.configuration.async do |notice|
  Thread.new { Airbrake.sender.send_to_airbrake(notice) }
end

Chore.add_hook(:on_failure) do |msg,error|
  Airbrake.notify(error, Chore::Airbrake.build_reporting_options_for(msg))
end

Chore.add_hook(:within_fork) do |worker, &block|
  begin
    block.call(worker)
  rescue StandardError => e
    message = { :body => 'Error within fork.', :messages => worker.work.map(&:message) }
    Airbrake.notify(e, Chore::Airbrake.build_reporting_options_for(message))
    raise e
  end
end

module Chore
  def Chore.airbrake #:nodoc:
    Chore::Airbrake
  end

  class Airbrake #:nodoc:
    def self.options=(opts)
      @options = opts
    end

    def self.options
      @options
    end

    def self.build_reporting_options_for(message, opts=nil)
      message_class = message['class'] || 'Unknown message class'

      {
        :action => (message_class.respond_to?(:underscore) ? message_class.underscore : message_class),
        :parameters => {:message => message},
        :component => 'chore'
      }.merge(opts || self.options || {})
    end
  end
end
