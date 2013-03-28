require 'singleton'
require 'optparse'
require 'chore'
require 'rack'

module Chore

  class CLI
    include Singleton
    include Util

    def initialize
      @options = {}
      @registered_opts = {}
      @stopping = false
    end

    def registered_opts
      @registered_opts
    end

    def self.register_option(key,*args,&blk)
      instance.register_option(key,*args,&blk)
    end

    def register_option(key,*args,&blk)
      registered_opts[key] = {:args => args}
      registered_opts[key].merge!(:block => blk) if blk
    end

    def parse(args=ARGV)
      Chore.logger.level = Logger::WARN
      setup_options
      parse_opts(args)
      if @options[:config_file] 
        parse_config_file(@options[:config_file])
      end
      validate!
      boot_system
      detect_queues
      Chore.configure(options)
    end

    def run!
      @manager = Chore::Manager.new
      start_stat_server(@manager)
      @manager.start
    end

    def shutdown
      unless @stopping
        @stopping = true
        @manager.shutdown! if @manager
        exit(0)
      end
    end

    def parse_config_file(file)
      data = File.readlines(file).map(&:chomp).map(&:strip)
      parse_opts(data)
    end

    def setup_options
      register_option "queues", "-q", "--queues QUEUE1,QUEUE2", "Names of queues to process (default: all known)" do |arg|
        options[:queues] = arg.split(",")
      end

      register_option "except_queues", "-x", "--except QUEUE1,QUEUE2", "Process all queues (cannot specify --queues), except for the ones listed here" do |arg|
        options[:except_queues] = arg.split(",")
      end

      register_option "verbose", "-v", "--verbose", "Print more verbose output. Use twice to increase." do
        if Chore.logger.level > Logger::INFO
          Chore.logger.level = Logger::INFO
        elsif Chore.logger.level > Logger::DEBUG
          Chore.logger.level = Logger::DEBUG
        end
      end

      register_option "environment", '-e', '--environment ENV', "Application environment"

      register_option "config_file", '-c', '--config-file FILE', "Location of a file specifying additional chore configuration"

      register_option 'require', '-r', '--require [PATH|DIR]', "Location of Rails application with workers or file to require"

      register_option 'stats_port', '-p', '--stats-port PORT', 'Port to run the stats HTTP server on'

      register_option 'aws_access_key', '--aws-access-key KEY', 'Valid AWS Access Key'

      register_option 'aws_secret_key', '--aws-secret-key KEY', 'Valid AWS Secret Key'

      register_option 'num_workers', '--concurrency NUM', 'Number of workers to run concurrently'

      register_option 'worker_strategy', '--worker-strategy CLASS_NAME', 'Name of a class to use as the worker strategy (default: ForkedWorkerStrategy' do |arg|
        options[:worker_strategy] = constantize(arg)
      end

      register_option 'consumer', '--consumer CLASS_NAME', 'Name of a class to use as the queue consumer (default: SqsConsumer)' do |arg|
        options[:consumer] = constantize(arg)
      end

      register_option 'fetcher_strategy', '--fetcher-strategy CLASS_NAME', 'Name of a class to use as the fetching strategy (default: ThreadPerConsumerStrategy' do |arg|
        options[:fetcher_strategy] = constantize(arg)
      end

    end

    def parse_opts(argv)
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

      @parser.parse!(argv)
      env_overrides

      @options
    end

    private
    def options
      @options
    end

    def env_overrides
      @options[:aws_access_key] ||= ENV['AWS_ACCESS_KEY']
      @options[:aws_secret_key] ||= ENV['AWS_SECRET_KEY']
    end

    def detected_environment
      options[:environment] ||= ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    end

    def boot_system
      ENV['RACK_ENV'] = ENV['RAILS_ENV'] = detected_environment

      raise ArgumentError, "#{options[:require]} does not exist" unless File.exist?(options[:require])

      if File.directory?(options[:require])
        require 'rails'
        require File.expand_path("#{options[:require]}/config/environment.rb")
        ::Rails.application.eager_load!
      else
        require File.expand_path(options[:require])
      end
    end

    def detect_queues
      if (options[:queues] && options[:except_queues])
        raise ArgumentError, "Cannot specify both --except and --queues"
      end

      if !options[:queues] 
        options[:queues] = []
        Chore::Job.job_classes.each do |j|
          klazz = constantize(j)
          options[:queues] << klazz.options[:name]
          options[:queues] -= (options[:except_queues] || [])
        end
      end
    end

    def missing_option!(option)
      puts "Missing argument: #{option}"
      exit(255)
    end

    def validate!

      missing_option!("--require [PATH|DIR]") unless options[:require]
      missing_option!("--aws-access-key KEY") unless options[:aws_access_key]
      missing_option!("--aws-secret-key KEY") unless options[:aws_secret_key]

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

    def start_stat_server(manager)
      Thread.new do
        Rack::Handler::WEBrick.run(lambda { |env| [200, {"Content-Type" => "application/json"}, [manager.report]] }, :Port => options[:stats_port] || 9090)
      end
    end
  end
end

