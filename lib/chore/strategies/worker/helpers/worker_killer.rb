require 'get_process_mem'

module Chore
  module Strategy
    class WorkerKiller  #:nodoc:
      def initialize
        @memory_limit = Chore.config.memory_limit_bytes
        @request_limit = Chore.config.request_limit
        @check_cycle = Chore.config.worker_check_cycle || 16
        @check_count = 0
        @current_requests = 0
      end

      def check_memory
        return if @memory_limit.nil? || (@memory_limit == 0)
        @check_count += 1

        if @check_count == @check_cycle
          rss = GetProcessMem.new.bytes.to_i
          if rss > @memory_limit
            Chore.logger.info "WK: (pid: #{Process.pid}) exceeded memory limit (#{rss.to_i} bytes > #{@memory_limit} bytes)"
            Chore.run_hooks_for(:worker_mem_kill)
            exit(true)
          end
          @check_count = 0
        end
      end

      def check_requests
        return if @request_limit.nil? || (@request_limit == 0)

        if (@current_requests += 1) >= @request_limit
          Chore.logger.info "WK: (pid: #{Process.pid}) exceeded max number of requests (limit: #{@request_limit})"
          Chore.run_hooks_for(:worker_req_kill)
          exit(true)
        end
      end
    end
  end
end
