$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'chore'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

class FakePublisher < Chore::Publisher
  def publish(job)
    call_publish_hooks(job)
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

 def start
  until FakePublisher.queue.empty?
    message = FakePublisher.queue.pop
    begin
      message = decode_job(message)
      puts message.inspect
      klass = constantize(message['job'])
      break unless run_hooks_for(:before_perform,*message['params'])
      klass.perform(*message['params'])
      run_hooks_for(:after_perform,*message['params'])
    rescue
      run_hooks_for(:on_failure,*message['params'])
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
