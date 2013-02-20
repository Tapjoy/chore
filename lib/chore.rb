require 'ostruct'
$:<< File.dirname(__FILE__)
require 'chore/util'
require 'chore/hooks'
require 'chore/json_encoder'

require 'chore/consumer'
require 'chore/publisher'
require 'chore/strategies/single_consumer_strategy'
require 'chore/strategies/thread_per_consumer_strategy'
require 'chore/consumers/sqs_consumer'
require 'chore/fetcher'
require 'chore/manager'
require 'chore/job'

module Chore
  VERSION = '0.0.1'

  # Simple class to hold job processing information. Stubbed as a Struct right now
  # but left as a class in case we need more methods soon.
  class UnitOfWork < Struct.new(:id,:message,:consumer); end;

  # Wrapper around an OpenStruct to define configuration data
  # (TODO): Add required opts, and validate that they're set
  Configuration = OpenStruct

  DEFAULT_OPTIONS = {
    :num_workers => 1, 
    :worker_strategy => SingleWorkerStrategy, 
    :consumer => SQSConsumer,
    :fetcher => Fetcher,
    :fetcher_strategy => ThreadPerConsumerStrategy,
    :batch_size => 50
  }

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

  def self.run_hooks_for(name)
    hooks = self.hooks_for(name)
    hooks.each(&:call) unless hooks.nil? || hooks.empty?
  end

  def self.configure(opts={})
    @config = Chore::Configuration.new(DEFAULT_OPTIONS.merge(opts))
    yield @config if block_given?
  end

  def self.config
    @config ||= self.configure
  end

end
