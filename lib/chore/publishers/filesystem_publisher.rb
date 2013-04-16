require 'chore/consumers/filesystem_queue'

# See the top of FilesystemConsumer for comments on how this works
module Chore
  class FilesystemPublisher < Publisher
    include FilesystemQueue
    
    def publish(queue_name,job)
      File.open(filename(queue_name, job[:class].to_s), "w") do |f|
        f.write(job.to_json)
      end
    end

    # create a unique filename for a job in a queue based on queue name, job name and date
    def filename(queue_name, job_name)
      now = Time.now.strftime "%Y%m%d-%H%M%S-%6N"
      i = 0
      prefix = "#{queue_name}-#{job_name}-#{now}"
      name = File.join(new_dir(queue_name), "#{prefix}-#{i}.job")
      while File.exist?(name)
        name = File.join(new_dir(queue_name), "#{prefix}-#{i += 1}.job")
      end
      name
    end
  end
end