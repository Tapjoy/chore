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

RSpec.configure do |config|
  config.after(:each) do
    FakePublisher.reset!
  end
end
