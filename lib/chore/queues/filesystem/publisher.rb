require 'chore/queues/filesystem/filesystem_queue'

module Chore
  module Queues
    module Filesystem

      # Publisher for writing jobs to the local filesystem. Useful for testing in offline environments or
      # when queuing implementations are irrelevent to the task at hand, such as local development of new jobs.
      class Publisher < Chore::Publisher
        # See the top of FilesystemConsumer for comments on how this works
        include FilesystemQueue

        # use of mutex and file locking should make this both threadsafe and safe for multiple
        # processes to use the same queue directory simultaneously. 
        def publish(queue_name,job)
          # First try encoding the job to avoid writing empty job files if this fails
          encoded_job = encode_job(job)

          published = false
          while !published
            # keep trying to get a file with nothing in it meaning we just created it
            # as opposed to us getting someone else's file that hasn't been processed yet.
            File.open(filename(queue_name, job[:class].to_s), "a") do |f|
              if f.flock(File::LOCK_EX | File::LOCK_NB) && f.size == 0
                f.write(encoded_job)
                published = true
              end
            end
          end
        end

        # create a unique filename for a job in a queue based on queue name, job name and date
        def filename(queue_name, job_name)
          now = Time.now.strftime "%Y%m%d-%H%M%S-%6N"
          previous_attempts = 0
          pid = Process.pid
          File.join(new_dir(queue_name), "#{queue_name}-#{job_name}-#{pid}-#{now}.#{previous_attempts}.job")
        end
      end
    end
  end
end
