require 'multi_json'
require 'chore/worker'
require 'chore/fetcher'

module Chore
  # Manages the interactions between fetching messages (Consumer Strategy), and working over them (Worker Strategy)
  class Manager
    include Util

    def initialize()
      Chore.logger.info "Booting Chore #{Chore::VERSION}"
      Chore.logger.debug { Chore.config.inspect }
      procline("#{Chore.config.master_procline}:Started:#{Time.now}")
      @started_at = nil
      @worker_strategy = Chore.config.worker_strategy.new(self)
      @fetcher = Chore.config.fetcher.new(self)
      @stopping = false
    end

    # Start the Manager. This calls both the #start method of the configured Worker Strategy, as well as Fetcher#start.
    def start
      Chore.run_hooks_for(:before_start)
      @started_at = Time.now
      @worker_strategy.start
      @fetcher.start
    end

    # Shut down the Manager, the Worker Strategy, and the Fetcher. This calls the +:before_shutdown+ hook.
    def shutdown!
      unless @stopping
        Chore.logger.info "Manager shutting down started"
        @stopping = true
        Chore.run_hooks_for(:before_shutdown)
        @fetcher.stop!
        @worker_strategy.stop!
        Chore.logger.info "Manager shutting down completed"
      end
    end

    # Take in an amount of +work+ (either an Array of, or a single UnitOfWork), and pass it down for the
    # worker strategy to process. <b>This method is blocking</b>. It will continue to attempt to assign the work via
    # the worker strategy, until it accepts it. It is up to the strategy to determine what cases it is allowed to accept
    # work. The blocking semantic of this method is to prevent the Fetcher from getting messages off of the queue faster
    # than they can be consumed.
    def assign(work)
      Chore.logger.debug { "Manager#assign: No. of UnitsOfWork: #{work.length})" }
      work.each do | item |
        Chore.run_hooks_for(:before_send_to_worker, item)
      end
      @worker_strategy.assign(work) unless @stopping
    end

    # returns up to n from the throttled consumer queue
    def fetch_work(n)
      @fetcher.provide_work(n)
    end

    # gives work back to the fetcher in case it couldn't be assigned
    def return_work(work_units)
      @fetcher.return_work(work_units)
    end
  end
end
