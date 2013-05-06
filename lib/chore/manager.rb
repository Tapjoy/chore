require 'json'
require 'chore/worker'
require 'chore/fetcher'

module Chore
  class Manager

    def initialize()
      Chore.logger.info "Booting Chore #{Chore::VERSION}"
      Chore.logger.debug { Chore.config.inspect }
      @started_at = nil
      @worker_strategy = Chore.config.worker_strategy.new(self)
      @fetcher = Chore.config.fetcher.new(self)
      @processed = 0
      @stopping = false
    end

    #
    # Start the Manager. This calls both the #start method of the configured Worker Strategy, as well as Fetcher#start.
    #
    def start
      @started_at = Time.now
      @worker_strategy.start
      @fetcher.start
    end

    #
    # Shut down the Manager, the Worker Strategy, and the Fetcher. This calls the +:before_shutdown+ hook.
    #
    def shutdown!
      unless @stopping
        Chore.logger.info "Manager shutting down"
        @stopping = true
        Chore.run_hooks_for(:before_shutdown)
        @worker_strategy.stop!
        @fetcher.stop!
      end
    end

    #
    # Take in an amount of +work+ (either an Array of, or a single UnitOfWork), and pass it down for the
    # worker strategy to process. <b>This method is blocking</b>. It will continue to attempt to assign the work via
    # the worker strategy, until it accepts it. It is up to the strategy to determine what cases it is allowed to accept
    # work. The blocking semantic of this method is to prevent the Fetcher from getting messages off of the queue faster 
    # than they can be consumed.
    #
    def assign(work)
      Chore.logger.debug { "Manager#assign(#{work.inspect})" }
      assigned = false
      until assigned 
        break if @stopping
        assigned = @worker_strategy.assign(work)
        if assigned
          Chore.stats.add(:batches)
        end

        sleep(0.2)
      end
    end

    #
    # Generate data for the internal Chore stat server. Should return JSON data representing the current state of the 
    # process. The default data set is:
    #
    # * +master_started_at+: the timestamp of when the Chore process started up
    # * +queues+: the list of queues this process is configured to consume
    # * +active_workers+: an array of Chore::Worker objects (will pass through a call to to_json)
    # * +stats+: the data inside of Chore.stats. This will include recently processed jobs, and other data that may be 
    # used to do some simple per-server graphing.
    def report
      {
        'master_started_at' => @started_at.to_i, 
        'queues' => Chore.config.queues,
        'active_workers' => @worker_strategy.workers,
        'stats' => Chore.stats
      }.to_json
    end
  end
end
