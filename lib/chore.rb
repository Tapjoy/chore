require 'ostruct'
require 'logger'
require 'zk'

$:<< File.join(File.dirname(__FILE__), 'chore')
require 'util'
require 'hooks'
require 'json_encoder'
require 'stats'
require 'version'

require 'consumer'
require 'publisher'

Dir[File.join(File.dirname(__FILE__), 'chore', 'strategies', '*.rb')].each {|f| require f }
Dir[File.join(File.dirname(__FILE__), 'chore', 'consumers', '*.rb')].each {|f| require f }

require 'fetcher'
require 'manager'
require 'job'
require 'semaphore'
require 'lease'

module Chore
  VERSION = Chore::Version::STRING

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
