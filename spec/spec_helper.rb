$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'timecop'
require 'chore'
require 'test_job'

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

TestMessage = Struct.new(:handle, :receipt_handle, :queue, :body, :receive_count) do
  def empty?
    false
  end

  def queue_name
    self.queue.name
  end

  def id
    self.handle
  end

  # Structs define a to_a behavior that is not compatible with array splatting. Remove it so that
  # [*message] on a struct will behave the same as on a string.
  undef_method :to_a
end


RSpec.configure do |config|
  config.include Chore::Util
  config.before do
    Chore.configure do |c|
      c.aws_access_key = ""
      c.aws_secret_key = ""
    end
    Chore.logger = Logger.new('/dev/null')

    # Reset CLI singleton
    Singleton.send(:__init__, Chore::CLI)

    # Reset configuration
    Chore.instance_eval { @config = nil }
  end

  config.after(:each) do
    FakePublisher.reset!
  end
end
