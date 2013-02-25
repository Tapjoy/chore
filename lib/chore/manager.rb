require 'json'
require 'chore/worker'
require 'chore/fetcher'

module Chore
  class Manager
    WORKERS = {}

    def initialize()
      @worker_strategy = Chore.config.worker_strategy.new(self)
      @fetcher = Chore.config.fetcher.new(self)
      @processed = 0
    end

    def start
      @fetcher.start
    end

    def assign(work)
      Chore.logger.debug "Manager Assign: "
      assigned = false
      until assigned 
        assigned = @worker_strategy.assign(work)
        if assigned
          @processed += 1
        end

        sleep(0.2)
      end
    end

    def report
      {'workers' => @worker_strategy.workers_available?, 'processed' => @processed}.to_json
    end
  end
end
