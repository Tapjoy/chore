require 'ostruct'

Dir[File.join(File.dirname(__FILE__), "chore", "*.rb")].each {|f| require f }
Dir[File.join(File.dirname(__FILE__), "chore", "*", "*.rb")].each {|f| require f }

module Chore
  VERSION = '0.0.1'

  # Simple class to hold job processing information. Stubbed as a Struct right now
  # but left as a class in case we need more methods soon.
  class UnitOfWork < Struct.new(:id,:message,:consumer); end;

  # Wrapper around an OpenStruct to define configuration data
  Configuration = OpenStruct

  DEFAULT_OPTIONS = {
    :num_workers => 1, 
    :worker_strategy => SingleWorkerStrategy, 
    :consumer => SQSConsumer,
    :fetcher => Fetcher,
    :fetcher_strategy => SingleConsumerStrategy
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

  def self.configure
    @config = Chore::Configuration.new(DEFAULT_OPTIONS)
    yield @config
  end

  def self.config
    @config ||= Chore::Configuration.new(DEFAULT_OPTIONS)
  end

end
