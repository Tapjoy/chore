$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'chore'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

class FakePublisher < Chore::Publisher
  def publish(job)
    self.class.queue.push(encode_job(job))
  end

  ## Test methods
  class << self
    def queue
      @@queue ||= []
    end

    def reset!
      @@queue = nil
    end
  end
end

class FakeWorker < Chore::Worker
 def setup
  # noop
 end

 def start(messages,manager,consumer)
  messages.each do |message|
    begin
      message = decode_job(message)
      puts message.inspect
      klass = constantize(message['class'])
      begin
        #break unless klass.run_hooks_for(:before_perform,*message['args'])
        klass.perform(*message['args'])
        #klass.run_hooks_for(:after_perform,*message['args'])
      rescue
        #klass.run_hooks_for(:on_failure,*message['args'])
      end
    end
  end
 end

 ## Test methods
 class << self
  def reset!
  end
 end
end

RSpec.configure do |config|
  config.after(:each) do
    FakePublisher.reset!
    FakeWorker.reset!
  end
end
