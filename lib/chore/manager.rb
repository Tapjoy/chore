require 'json'
require 'chore/worker'
require 'chore/fetcher'

module Chore
  # Manages the interactions between fetching messages (Consumer Strategy), and working over them (Worker Strategy)
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

    # Start the Manager. This calls both the #start method of the configured Worker Strategy, as well as Fetcher#start.
    def start
      @started_at = Time.now
      @worker_strategy.start
      @fetcher.start
    end

    # Shut down the Manager, the Worker Strategy, and the Fetcher. This calls the +:before_shutdown+ hook.
    def shutdown!
      unless @stopping
        Chore.logger.info "Manager shutting down"
        @stopping = true
        Chore.run_hooks_for(:before_shutdown)
        @fetcher.stop!
        @worker_strategy.stop!
      end
    end

    # Take in an amount of +work+ (either an Array of, or a single UnitOfWork), and pass it down for the
    # worker strategy to process. <b>This method is blocking</b>. It will continue to attempt to assign the work via
    # the worker strategy, until it accepts it. It is up to the strategy to determine what cases it is allowed to accept
    # work. The blocking semantic of this method is to prevent the Fetcher from getting messages off of the queue faster
    # than they can be consumed.
    def assign(work)
      Chore.logger.debug { "Manager#assign: No. of UnitsOfWork: #{work.length})" }
      @worker_strategy.assign(work) unless @stopping
    end
  end
end
