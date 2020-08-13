require 'pp'
require 'singleton'
require 'optparse'
require 'chore'
require 'erb'
require 'set'

require 'chore/manager'

module Chore #:nodoc:

  # Class that handles the command line interactions in Chore.
  # It primarily is responsible for invoking the Chore process with the provided configuration
  # to begin processing jobs.
  class CLI
    include Singleton
    include Util

    attr_reader :options, :registered_opts

    def initialize
      @options = {}
      @registered_opts = {}
      @stopping = false
    end

    #
    # +register_option+ is a method for plugins or other components to register command-line config options.
    # * <tt>key</tt> is the name for this option that can be referenced from Chore.config.+key+
    # * <tt>*args</tt> is an <tt>OptionParser</tt> style list of options.
    # * <tt>&blk</tt> is an option block, passed to <tt>OptionParser</tt>
    #
    # === Examples
    #   Chore::CLI.register_option 'sample', '-s', '--sample-key SOME_VAL', 'A description of this value'
    #
    #   Chore::CLI.register_option 'something', '-g', '--something-complex VALUE', 'A description' do |arg|
    #     # make sure your key here matches the key you register
    #     options[:something] arg.split(',')
    #   end
    def self.register_option(key,*args,&blk)
      instance.register_option(key,*args,&blk)
    end

    def register_option(key,*args,&blk) #:nodoc:
      registered_opts[key] = {:args => args}
      registered_opts[key].merge!(:block => blk) if blk
    end

    # Start up the consuming side of the application. This calls Chore::Manager#start.
    def run!(args=ARGV)
      parse(args)
      @manager = Chore::Manager.new
      @manager.start
    end

    # Begins the Chore shutdown process. This will call Chore::Manager#shutdown if it is not already in the process of stopping
    # Exits with code 0
    def shutdown
      unless @stopping
        @stopping = true
        @manager.shutdown! if @manager
        exit(0)
      end
    end

    def parse_config_file(file, ignore_errors = false) #:nodoc:
      data = File.read(file)
      data = ERB.new(data).result
      parse_opts(data.split(/\s/).map!(&:chomp).map!(&:strip), ignore_errors)
    end

    def parse(args=ARGV) #:nodoc:
      Chore.configuring = true
      setup_options

      # parse once to load the config file & require options
      # any invalid options are ignored the first time around since booting the
      # system may register additional options from 3rd-party libs
      parse_opts(args, true)
      parse_config_file(@options[:config_file], true) if @options[:config_file]

      validate!
      boot_system

      # parse again to pick up options required by loaded classes
      # any invalid options will raise an exception this time
      parse_opts(args)
      parse_config_file(@options[:config_file]) if @options[:config_file]
      detect_queues
      Chore.configure(options)
      Chore.configuring = false
      validate_strategy!
    end

    private

    def setup_options #:nodoc:
      register_option "queues", "-q", "--queues QUEUE1,QUEUE2", "Names of queues to process (default: all known)" do |arg|
        # This will remove duplicates. We ultimately force this to be a Set further below
        options[:queues] = Set.new(arg.split(","))
      end

      register_option "except_queues", "-x", "--except QUEUE1,QUEUE2", "Process all queues (cannot specify --queues), except for the ones listed here" do |arg|
        options[:except_queues] = arg.split(",")
      end

      register_option "verbose", "-v", "--verbose", "Print more verbose output. Use twice to increase." do
        options[:log_level] ||= Logger::WARN
        options[:log_level] = options[:log_level] - 1 if options[:log_level] > 0
      end

      register_option "environment", '-e', '--environment ENV', "Application environment"

      register_option "config_file", '-c', '--config-file FILE', "Location of a file specifying additional chore configuration"

      register_option 'require', '-r', '--require [PATH|DIR]', "Location of Rails application with workers or file to require"

      register_option 'num_workers', '--concurrency NUM', Integer, 'Number of workers to run concurrently'

      register_option 'queue_prefix', '--queue-prefix PREFIX', "Prefix to use on Queue names to prevent non-determinism in testing environments" do |arg|
        options[:queue_prefix] = arg.downcase << "_"
      end

      register_option 'max_attempts', '--max-attempts NUM', Integer, 'Number of times to attempt failed jobs'

      register_option 'worker_strategy', '--worker-strategy CLASS_NAME', 'Name of a class to use as the worker strategy (default: ForkedWorkerStrategy' do |arg|
        options[:worker_strategy] = constantize(arg)
      end

      register_option 'consumer', '--consumer CLASS_NAME', 'Name of a class to use as the queue consumer (default: SqsConsumer)' do |arg|
        options[:consumer] = constantize(arg)
      end

      register_option 'consumer_strategy', '--consumer-strategy CLASS_NAME', 'Name of a class to use as the consumer strategy (default: Chore::Strategy::ThreadedConsumerStrategy' do |arg|
        options[:consumer_strategy] = constantize(arg)
      end

      register_option 'consumer_sleep_interval', '--consumer-sleep-interval INTERVAL', Float, 'Length of time in seconds to sleep when the consumer does not find any messages (default: 1)'

      register_option 'payload_handler', '--payload_handler CLASS_NAME', 'Name of a class to use as the payload handler (default: Chore::Job)' do |arg|
        options[:payload_handler] = constantize(arg)
      end

      register_option 'shutdown_timeout', '--shutdown-timeout SECONDS', Float, "Upon shutdown, the number of seconds to wait before force killing worker strategies (default: #{Chore::DEFAULT_OPTIONS[:shutdown_timeout]})"

      register_option 'dupe_on_cache_failure', '--dupe-on-cache-failure BOOLEAN', 'Determines the deduping behavior when a cache connection error occurs. When set to false, the message is assumed not to be a duplicate. (default: false)'

      register_option 'queue_polling_size', '--queue_polling_size NUM', Integer, 'Amount of messages to grab on each request (default: 10)'
    end

    def parse_opts(argv, ignore_errors = false) #:nodoc:
      @options ||= {}
      @parser = OptionParser.new do |o|
        registered_opts.each do |key,opt|
          if opt[:block]
            o.on(*opt[:args],&opt[:block])
          else
            o.on(*opt[:args]) do |arg|
              options[key.to_sym] = arg
            end
          end
        end
      end

      @parser.banner = "chore [options]"

      @parser.on_tail "-h", "--help", "Show help" do
        puts @parser
        exit 1
      end

      # This will parse arguments in order, continuing even if invalid options
      # are encountered
      argv = argv.dup
      begin
        @parser.parse(argv)
      rescue OptionParser::InvalidOption => ex
        if ignore_errors
          # Drop everything up to (and including) the invalid argument
          # and start parsing again
          invalid_arg = ex.args[0]
          argv = argv.drop(argv.index(invalid_arg) + 1)
          retry
        else
          raise
        end
      end

      @options
    end


    def detected_environment #:nodoc:
      options[:environment] ||= ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    end

    def boot_system #:nodoc:
      ENV['RACK_ENV'] = ENV['RAILS_ENV'] = detected_environment

      raise ArgumentError, "#{options[:require]} does not exist" unless File.exist?(options[:require])

      if File.directory?(options[:require])
        require 'rails'
        require 'chore/railtie'
        require File.expand_path("#{options[:require]}/config/environment.rb")
        ::Rails.application.eager_load!
      else
        # Pre-load any Bundler dependencies now, so that the CLI parser has them loaded
        # prior to intrpretting the command line args for things like consumers/producers
        Bundler.require if defined?(Bundler)
        require File.expand_path(options[:require])
      end
    end

    def detect_queues #:nodoc:
      if (options[:queues] && options[:except_queues])
        raise ArgumentError, "Cannot specify both --except and --queues"
      end

      ### Ensure after loading the app, that we have the prefix set (quirk of using Chore::Job#prefixed_queue_name to do the prefixing)
      Chore.config.queue_prefix ||= options[:queue_prefix]

      ### For ease, make sure except_queues is an array
      options[:except_queues] ||= []

      ### Generate a hash of all possible queues and their prefixed_names
      queue_map = Chore::Job.job_classes.inject({}) do |hsh,j|
        klazz = constantize(j)
        hsh[klazz.options[:name]] = klazz.prefixed_queue_name if klazz.options[:name]
        hsh
      end

      ### If we passed in a queues option, use it as our working set, otherwise use all the queues
      if options[:queues]
        queues_to_use = options[:queues]
      else
        queues_to_use = queue_map.keys
      end

      ### Remove the excepted queues from our working set
      queues_to_use = queues_to_use - options[:except_queues]

      ### Set options[:queues] to the prefixed value of the current working set
      options[:queues] = queues_to_use.inject([]) do |queues,k|
        raise ArgumentError, "You have specified a queue #{k} for which you have no corresponding Job class" unless queue_map.has_key?(k)
        queues << queue_map[k]
        queues
      end

      raise ArgumentError, "No queues specified. Either include classes that include Chore::Job, or specify the --queues option" if options[:queues].empty?
    end

    def missing_option!(option) #:nodoc:
      puts "Missing argument: #{option}"
      exit(255)
    end

    def validate! #:nodoc:
      missing_option!("--require [PATH|DIR]") unless options[:require]

      if !File.exist?(options[:require]) ||
         (File.directory?(options[:require]) && !File.exist?("#{options[:require]}/config/application.rb"))
        puts "=================================================================="
        puts "  Please point chore to a Rails 3 application or a Ruby file    "
        puts "  to load your worker classes with -r [DIR|FILE]."
        puts "=================================================================="
        puts @parser
        exit(1)
      end
    end

    def validate_strategy!
      consumer_strategy = Chore.config.consumer_strategy.to_s
      worker_strategy = Chore.config.worker_strategy.to_s

      throttled_consumer = 'Chore::Strategy::ThrottledConsumerStrategy'
      preforked_worker = 'Chore::Strategy::PreForkedWorkerStrategy'

      if consumer_strategy == throttled_consumer || worker_strategy == preforked_worker
        unless consumer_strategy == throttled_consumer && worker_strategy == preforked_worker
          puts "=================================================================="
          puts "  PreForkedWorkerStrategy may only be paired with   "
          puts "  ThrottledConsumerStrategy or vice versa  "
          puts "  Please check your configurations "
          puts "=================================================================="
          exit(1)
        end
      end
    end
  end
end
