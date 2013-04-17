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
require 'chore/consumers/locking_sqs_consumer'
require 'chore/publishers/sqs_publisher'

# We have a number of things that can live here. I don't want to track
['consumers','publishers','strategies/**'].each do |p|
  Dir[File.join(File.dirname(__FILE__),'chore',p,'*.rb')].each {|f| require f}
end

module Chore
  VERSION = Chore::Version::STRING
  
  # Simple class to hold job processing information. Stubbed as a Struct right now
  # but left as a class in case we need more methods soon.
  class UnitOfWork < Struct.new(:id,:message,:consumer); end;

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

  DEFAULT_OPTIONS = {
    :num_workers => 4,
    :threads_per_queue => 1,
    :worker_strategy => ForkedWorkerStrategy,
    :consumer => SQSConsumer,
    :fetcher => Fetcher,
    :fetcher_strategy => ThreadedConsumerStrategy,
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
    @config = (@config ? @config.merge_hash(opts) : Chore::Configuration.new(DEFAULT_OPTIONS.merge(opts)))
    yield @config if block_given?
    @config
  end

  def self.config
    @config ||= self.configure
  end

end
