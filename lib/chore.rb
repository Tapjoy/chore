require 'ostruct'
require 'logger'
# Require chore files
require 'chore/version'

require 'chore/unit_of_work'
require 'chore/configuration'
require 'chore/cli'
require 'chore/consumer'
require 'chore/job'
require 'chore/encoders/json_encoder'
require 'chore/manager'
require 'chore/publisher'
require 'chore/util'
require 'chore/worker'
require 'chore/batched_worker'
require 'chore/publisher'

# We have a number of things that can live here. I don't want to track
['queues/**','strategies/**'].each do |p|
  Dir[File.join(File.dirname(__FILE__),'chore',p,'*.rb')].each {|f| require f}
end

module Chore #:nodoc:
  extend Util
  VERSION = Chore::Version::STRING #:nodoc:

  # The default configuration options for Chore.
  DEFAULT_OPTIONS = {
    :require               => "./",
    :num_workers           => 4,
    :threads_per_queue     => 1,
    :worker_strategy       => Strategy::ForkedWorkerStrategy,
    :consumer              => Queues::SQS::Consumer,
    :fetcher               => Fetcher,
    :consumer_strategy     => Strategy::ThreadedConsumerStrategy,
    :batch_size            => 50,
    :log_level             => Logger::WARN,
    :log_path              => STDOUT,
    :default_queue_timeout => (12 * 60 * 60), # 12 hours
    :shutdown_timeout      => (2 * 60),
    :max_attempts          => 1.0 / 0.0, # Infinity
    :dupe_on_cache_failure => false,
    :payload_handler => Chore::Job
  }

  class << self
    attr_accessor :logger
  end

  # Access Chore's logger in a memoized fashion. Will create an instance of the logger if
  # one doesn't already exist.
  def self.logger
    @logger ||= Logger.new(config.log_path).tap do |l|
      l.level = config.log_level
      l.formatter = lambda do |severity, datetime, progname, msg|
         "[#{datetime} (#{Process.pid})] #{severity} : #{msg}\n"
      end
    end
  end

  # Reopens any open files.  This will match any logfile that was opened by Chore,
  # Rails, or any other library.
  def self.reopen_logs
    # Find any open file in the process
    files = []
    ObjectSpace.each_object(File) {|file| files << file unless file.closed?}

    files.each do |file|
      begin
        file.reopen(file.path, 'a+')
        file.sync = true
      rescue
        # Can't reopen -- ignore / skip the file
      end
    end
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
  #
  # == Before / After hooks
  #
  # If this is invoked for before / after hooks (i.e. no block is passed), then the
  # hooks will be invoked in the order in which they're defined.
  #
  # For example:
  #
  #   add_hook(:before_fork) {|worker| puts 1 }
  #   add_hook(:before_fork) {|worker| puts 2 }
  #   add_hook(:before_fork) {|worker| puts 3 }
  #   
  #   run_hooks_for(:before_fork, worker)
  #   
  #   # ...will produce the following output
  #   => 1
  #   => 2
  #   => 3
  #
  # == Around hooks
  #
  # If this is invoked for around hooks (i.e. a block is passed), then the hooks
  # will be invoked in the order in which they're defined, with the passed block
  # being invoked last after the hooks yield.
  #
  # For example:
  #
  #   add_hook(:around_fork) {|worker, &block| puts 'before 1'; block.call; puts 'after 1'}
  #   add_hook(:around_fork) {|worker, &block| puts 'before 2'; block.call; puts 'after 2'}
  #   add_hook(:around_fork) {|worker, &block| puts 'before 3'; block.call; puts 'after 3'}
  #   
  #   run_hooks_for(:around_fork, worker) { puts 'block' }
  #   
  #   # ...will produce the following output
  #   => before 1
  #   => before 2
  #   => before 3
  #   => block
  #   => after 3
  #   => after 2
  #   => after 1
  #
  # You can imagine the callback order to be U shaped where logic *prior* to yielding
  # is called in the order it's defined and logic *after* yielding is called in
  # reverse order.  At the bottom of the U is when the block passed into +run_hooks_for+
  # gets invoked.
  def self.run_hooks_for(name,*args,&block)
    if block
      run_around_hooks_for(name, args, &block)
    else
      hooks = self.hooks_for(name)
      hooks.each {|h| h.call(*args, &block)} unless hooks.nil? || hooks.empty?
    end
  end

  class << self
    private
    # Runs the global *around* hooks.  This is similar to +run_hooks_for+ except it
    # passing a block into each hook.
    def run_around_hooks_for(name, args, index = 0, &block)
      hooks = self.hooks_for(name)

      if hook = hooks[index]
        hook.call(*args) do
          # Once the hook yields, call the next one
          run_around_hooks_for(name, args, index + 1, &block)
        end
      else
        # There are no more hooks: call the black passed into +run_hooks_for+.
        # After this is called, the hooks will then execute their logic after the
        # yield in reverse order.
        block.call
      end
    end
  end

  # Configure global chore options. Takes a hash for +opts+.
  # This includes things like the current Worker Strategy (+:worker_strategy+), the default Consumer (+:consumer+), and the default Consumer Strategy(+:consumer_strategy).
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

  # Helper flag for rails/web app chore initializers to use so that chore does not re-load itself during requirement loading
  def self.configuring?
    @configuring ||= false
  end

  # Setter for chore to indicate that it's in the middle of configuring itself
  def self.configuring=(value)
    @configuring = value
  end

  # List of queue_names as configured via Chore::Job including their prefix, if set.
  def self.prefixed_queue_names
    Chore::Job.job_classes.collect {|klass| c = constantize(klass); c.prefixed_queue_name}
  end
end

require 'chore/railtie' if defined?(Rails)
