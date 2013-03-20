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

    def start
      @started_at = Time.now
      @worker_strategy.start
      @fetcher.start
    end

    def shutdown!
      unless @stopping
        Chore.logger.info "Manager shutting down"
        @stopping = true
        @worker_strategy.stop!
        @fetcher.stop!
      end
    end

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

    def report
      {
        'master_started_at' => @started_at, 
        'queues' => Chore.config.queues,
        'active_workers' => @worker_strategy.workers,
        'stats' => Chore.stats
      }.to_json
    end
  end
end
