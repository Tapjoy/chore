require 'chore/queues/filesystem/filesystem_queue'

module Chore
  module Queues
    module Filesystem

      # Publisher for writing jobs to the local filesystem. Useful for testing in offline environments or
      # when queuing implementations are irrelevent to the task at hand, such as local development of new jobs.
      class Publisher < Chore::Publisher
        # See the top of FilesystemConsumer for comments on how this works
        include FilesystemQueue

        # Mutex for holding a lock over the files for this queue while they are in process
        FILE_MUTEX = Mutex.new

        # use of mutex and file locking should make this both threadsafe and safe for multiple
        # processes to use the same queue directory simultaneously. 
        def publish(queue_name,job)
          # First try encoding the job to avoid writing empty job files if this fails
          encoded_job = job.to_json

          FILE_MUTEX.synchronize do
            while true
              # keep trying to get a file with nothing in it meaning we just created it
              # as opposed to us getting someone else's file that hasn't been processed yet.
              f = File.open(filename(queue_name, job[:class].to_s), "w")
              if f.flock(File::LOCK_EX | File::LOCK_NB) && f.size == 0
                begin
                  f.write(encoded_job)
                rescue StandardError => e
                  Chore.logger.error "#{e.class.name}: #{e.message}. Could not write #{job[:class]} job to '#{queue_name}' queue file."
                  Chore.logger.error e.backtrace.join("\n")
                ensure
                  f.flock(File::LOCK_UN)
                end
                break
              end
            end
          end
        end

        # create a unique filename for a job in a queue based on queue name, job name and date
        def filename(queue_name, job_name)
          now = Time.now.strftime "%Y%m%d-%H%M%S-%6N"
          previous_attempts = 0
          File.join(new_dir(queue_name), "#{queue_name}-#{job_name}-#{now}.#{previous_attempts}.job")
        end
      end
    end
  end
end
