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
          jobs_to_return = assign_jobs(jobs, workers)
          manager.return_work(jobs_to_return)
        end

        private

        def assign_jobs(jobs, workers)
          raise 'DW: assign_jobs got 0 workers' if workers.empty?
          jobs_to_return = []
          jobs.each_with_index do |job, i|
            raise 'DW: More Jobs than Sockets' if workers[i].nil?
            unless push_job_to_worker(job, workers[i])
              jobs_to_return << job
            end
          end

          jobs_to_return
        end

        def push_job_to_worker(job, worker)
          Chore.run_hooks_for(:before_send_to_worker, job)
          clear_ready(worker.socket)
          send_msg(worker.socket, job)
          true
        rescue => e
          Chore.logger.error "DW: Could not assign job #{job.inspect} (worker: #{worker.pid})\nException #{e.message} #{e.backtrace * "\n"}"
          
          # We generally shouldn't get into this situations since we've already
          # tested that we can read/write to the Worker's socket.  However,
          # the Worker could still fail between that check and pushing the
          # job, so we need to allow the work to be re-assigned to handle that
          # edge case.
          false
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
