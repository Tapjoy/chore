require 'chore/strategies/worker/helpers/ipc'

module Chore
  module Strategy
    class WorkDistributor #:nodoc:
      class << self
        include Ipc

        def fetch_and_assign_jobs(workers, manager)
          jobs = manager.fetch_work(workers.size)
          raise "DW: jobs needs to be a list got #{jobs.class}" unless jobs.is_a?(Array)
          if jobs.empty?
            # This conditon is due to the internal consumer queue being empty.
            # Assuming that the the consumer has to fetch from an external queue,
            # if we return here, we would create a tight loop that would use up
            # a lot the CPU's time. In order to prevent that, we wait for the
            # consumer queue to be populated, by sleeping. 
            sleep(0.1)
            return
          end
          assign_jobs(jobs, workers)
        end

        private

        def assign_jobs(jobs, workers)
          raise 'DW: assign_jobs got 0 workers' if workers.empty?
          jobs.each_with_index do |job, i|
            raise 'DW: More Jobs than Sockets' if workers[i].nil?
            push_job_to_worker(job, workers[i])
          end
        end

        def push_job_to_worker(job, worker)
          Chore.run_hooks_for(:before_send_to_worker, job)
          clear_ready(worker.socket)
          send_msg(worker.socket, job)
        rescue => e
          Chore.logger.error "DW: Could not assign job #{job.inspect}\nException #{e.message} #{e.backtrace * "\n"}"
        end

        private

        # Used for unit tests
        def sleep(n)
          Kernel.sleep(n)
        end
      end
    end
  end
end
