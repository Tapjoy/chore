require 'ostruct'
require 'logger'
require 'zk'

module Chore
  VERSION = Chore::Version::STRING

  autoload :CLI,                "chore/cli"
  autoload :Consumer,           "chore/consumer"
  autoload :DuplicateDetector,  "chore/duplicate_detector"
  autoload :Fetcher,            "chore/fetcher"
  autoload :Hooks,              "chore/hooks"
  autoload :Job,                "chore/job"
  autoload :JsonEncoder,        "chore/json_encoder"
  autoload :Lease,              "chore/lease"
  autoload :Manager,            "chore/manager"
  autoload :Publisher,          "chore/publisher"
  autoload :Semaphore,          "chore/semaphore"
  autoload :Stats,              "chore/stats"
  autoload :Util,               "chore/util"
  autoload :Worker,             "chore/worker"

  # Consumers
  autoload :SQSConsumer,        "chore/consumers/sqs_consumer"

  # Worker strategies
  autoload :ForkedWorkerStrategy,  "chore/strategies/worker/forked_worker_strategy"
  autoload :SingleWorkerStrategy,  "chore/strategies/worker/single_worker_strategy"

  # Consumer strategies
  autoload :SingleConsumerStrategy,    "chore/strategies/consumer/single_consumer_strategy"
  autoload :ThreadPerConsumerStrategy, "chore/strategies/consumer/thread_per_consumer_strategy"

  # Simple class to hold job processing information. Stubbed as a Struct right now
  # but left as a class in case we need more methods soon.
  class UnitOfWork < Struct.new(:id,:message,:consumer); end;

  # Wrapper around an OpenStruct to define configuration data
  # (TODO): Add required opts, and validate that they're set
  Configuration = OpenStruct

  DEFAULT_OPTIONS = {
    :num_workers => 4,
    :worker_strategy => ForkedWorkerStrategy,
    :consumer => SQSConsumer,
    :fetcher => Fetcher,
    :fetcher_strategy => ThreadPerConsumerStrategy,
    :batch_size => 50
  }

  class << self
    attr_accessor :logger, :stats
  end

  def self.logger
    @logger ||= begin
      STDOUT.sync = true
      Logger.new(STDOUT)
    end
  end

  def self.stats
    @stats ||= Stats.new
  end

  def self.add_hook(name,&blk)
    @@hooks ||= {}
    (@@hooks[name.to_sym] ||= []) << blk
  end

  def self.hooks_for(name)
    @@hooks ||= {}
    @@hooks[name.to_sym] || []
  end

  def self.clear_hooks!
    @@hooks = {}
  end

  def self.run_hooks_for(name,*args)
    hooks = self.hooks_for(name)
    hooks.each {|h| h.call(*args)} unless hooks.nil? || hooks.empty?
  end

  def self.configure(opts={})
    @config = Chore::Configuration.new(DEFAULT_OPTIONS.merge(opts))
    yield @config if block_given?
  end

  def self.config
    @config ||= self.configure
  end

end
