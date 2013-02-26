require 'json'
require 'chore/worker'
require 'chore/fetcher'

module Chore
  class Manager

    def initialize()
      Chore.logger.info "Booting Chore #{Chore::VERSION}"
      Chore.logger.debug { Chore.config.inspect }
      @worker_strategy = Chore.config.worker_strategy.new(self)
      @fetcher = Chore.config.fetcher.new(self)
      @processed = 0
      @stopping = false
    end

    def start
      @fetcher.start
    end

    def shutdown!
      unless @stopping
        Chore.logger.info "Manager shutting down"
        @stopping = true
        @worker_strategy.stop!
        Chore::Fetcher.stop!
      end
    end

    def assign(work)
      Chore.logger.debug { "Manager#assign(#{work.inspect})" }
      assigned = false
      until assigned 
        break if @stopping
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
