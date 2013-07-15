require 'ostruct'
require 'logger'
# Require chore files
require 'chore/version'

require 'chore/cli'
require 'chore/consumer'
require 'chore/job'
require 'chore/json_encoder'
require 'chore/manager'
require 'chore/publisher'
require 'chore/stats'
require 'chore/util'
require 'chore/worker'
require 'chore/publisher'

# We have a number of things that can live here. I don't want to track
['queues/**','strategies/**'].each do |p|
  Dir[File.join(File.dirname(__FILE__),'chore',p,'*.rb')].each {|f| require f}
end

module Chore 
  VERSION = Chore::Version::STRING #:nodoc:
  # = Chore
  
  # Simple class to hold job processing information.
  # Has only three attributes:
  # * +:id+ The queue implementation specific identifier for this message.
  # * +:message+ The actual data of the message.
  # * +:consumer+ The consumer instance used to fetch this message. Most queue implementations won't need access to this, but some (RabbitMQ) will. So we
  # make sure to pass it along with each message. This instance will be used by the Worker for things like <tt>complete</tt> and </tt>reject</tt>.
  class UnitOfWork < Struct.new(:id,:message,:consumer);end;

  # Wrapper around an OpenStruct to define configuration data
  # (TODO): Add required opts, and validate that they're set
  class Configuration < OpenStruct
    def merge_hash(hsh={})
      hsh.keys.each do |k|
        self.send("#{k.to_sym}=",hsh[k])
      end
      self
    end
  end

  ##
  # The default configuration options for Chore.
  DEFAULT_OPTIONS = {
    :require => "./",
    :num_workers => 4,
    :threads_per_queue => 1,
    :worker_strategy => Strategy::ForkedWorkerStrategy,
    :consumer => Queues::SQS::Consumer,
    :fetcher => Fetcher,
    :fetcher_strategy => Strategy::ThreadedConsumerStrategy,
    :batch_size => 50
  }

  class << self
    attr_accessor :logger, :stats
  end

  # Access Chore's logger in a memoized fashion. Will create an instance of the logger if
  # one doesn't already exist.
  def self.logger
    @logger ||= begin
      STDOUT.sync = true
      Logger.new(STDOUT)
    end
  end

  def self.stats
    @stats ||= Stats.new
  end

  # Add a global hook for +name+. Will run +&blk+ when the hook is executed. 
  # Global hooks are any hooks that don't have access to an instance of a job.
  # See the docs on Hooks for a full list of global hooks.
  #
  # === Examples 
  #   Chore.add_hook_for(:after_fork) do
  #     SomeDB.reset_connection!
  #   end
  def self.add_hook(name,&blk)
    @@hooks ||= {}
    (@@hooks[name.to_sym] ||= []) << blk
  end

  # A helper to get a list of all the hooks for a given +name+
  def self.hooks_for(name)
    @@hooks ||= {}
    @@hooks[name.to_sym] || []
  end

  def self.clear_hooks! #:nodoc:
    @@hooks = {}
  end

  # Run the global hooks associated with a particular +name+ passing all +args+ to the registered block.
  def self.run_hooks_for(name,*args)
    hooks = self.hooks_for(name)
    hooks.each {|h| h.call(*args)} unless hooks.nil? || hooks.empty?
  end

  # Configure global chore options. Takes a hash for +opts+.
  # This includes things like the current Worker Strategy (+:worker_strategy+), the default Consumer (+:consumer+), and the default Fetcher Strategy(+:fetcher_strategy).
  # It's safe to call multiple times (will merge the new config, into the old)
  # This is used by the command line parsing code to setup Chore.
  # If a +block+ is given, <tt>configure</tt> will yield the config object, so you can set options directly.
  # === Examples
  #   Chore.configure({:worker_strategy => Chore::ForkedWorkerStrategy})
  #
  #   Chore.configure do |c|
  #     c.consumer = Chore::Queues::SQS::Consumer
  #     c.batch_size = 50
  #   end
  def self.configure(opts={})
    @config = (@config ? @config.merge_hash(opts) : Chore::Configuration.new(DEFAULT_OPTIONS.merge(opts)))
    yield @config if block_given?
    @config
  end

  # Return the current Chore configuration as specified by <tt>configure</tt>. You can chain config options off of this to
  # get access to current config data.
  # === Examples
  #   puts Chore.config.num_workers
  def self.config
    @config ||= self.configure
  end

  #
  # Helper flag for rails/web app chore initializers to use so that chore does not re-load itself during requirement loading
  #
  def self.configuring?
    @configuring ||= false
  end

  def self.configuring=(value)
    @configuring = value
  end
end
