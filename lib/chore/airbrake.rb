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
  msg_class = msg['class'] || 'Unknown message class'
  
  airbrake_opts = {}
  airbrake_opts[:action] = msg_class
  airbrake_opts[:parameters] = {:message => msg}
  airbrake_opts[:environment_name] = "Chore"
  airbrake_opts[:cgi_data] = ENV
  airbrake_opts.merge!(Chore::Airbrake.options) if Chore::Airbrake.options

  Chore.logger.debug {"Sending exception to airbrake. error: #{error}, opts: #{airbrake_opts}"}
  Airbrake.notify(error, airbrake_opts)
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
  end
end
