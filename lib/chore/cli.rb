require 'singleton'
require 'optparse'
require 'chore'
require 'rack'

module Chore
  class CLI
    include Singleton
    def initialize
      @options = {}
      @stopping = false
    end

    def parse(args=ARGV)
      Chore.logger.level = Logger::WARN
      @options = parse_opts(args)
      Chore.configure(@options)
      validate!
      boot_system
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

    def parse_opts(argv)
      opts = {}
      @parser = OptionParser.new do |o|
         o.on "-q", "--queue QUEUE1,QUEUE2", "Names of queues to process (default: all known)" do |arg|
          opts[:queues] = arg.split(",")
        end

        o.on "-v", "--verbose", "Print more verbose output" do
          Chore.logger.level = Logger::INFO
        end

        o.on "-VV", "--very-verbose", "Print the most verbose output" do
          Chore.logger.level = Logger::DEBUG
        end

        o.on '-e', '--environment ENV', "Application environment" do |arg|
          opts[:environment] = arg
        end

        o.on '-r', '--require [PATH|DIR]', "Location of Rails application with workers or file to require" do |arg|
          opts[:require] = arg
        end

        o.on '-p', '--stats-port PORT', 'Port to run the stats HTTP server on' do |arg|
          opts[:stats_port] = arg
        end

        o.on '--aws-access-key KEY', 'Valid AWS Access Key' do |arg|
          opts[:aws_access_key] = arg
        end

        o.on '--aws-secret-key KEY', 'Valid AWS Secret Key' do |arg|
          opts[:aws_secret_key] = arg
        end
      end
      @parser.banner = "chore [options]"

      @parser.on_tail "-h", "--help", "Show help" do
        puts @parser
        exit 1
      end

      @parser.parse!(ARGV)
      opts = env_overrides(opts)
      opts
    end

    private
    def options
      @options
    end

    def env_overrides(opts)
      opts[:aws_access_key] ||= ENV['AWS_ACCESS_KEY']
      opts[:aws_secret_key] ||= ENV['AWS_SECRET_KEY']
      opts
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

    def validate!
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

