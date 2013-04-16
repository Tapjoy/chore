require 'fileutils'
require 'chore/consumers/filesystem_queue'

# This is the consuming side of the file system queue. This class consumes jobs created by
# FilesystemPublisher#publish.  The root of the file system queue is configured in
# Chore.config.fs_queue_root. In there a directory will be created for each queue name.
# Each queue directory contains a directory called "new" and one called "inprogress".
# FilesystemPublisher#publish creates new job files in the "new" directory. This consumer
# polls that directory every 5 seconds for new jobs which are moved to "inprogress".
#
# Once complete job files are deleted.
# If rejected they are moved back into new and will be processed again.  This may not be the
# desired behavior long term and we may want to add configuration to this class to allow more
# creating failure handling and retrying. 
module Chore
  class FilesystemConsumer < Consumer
    include FilesystemQueue
    
    FILE_QUEUE_MUTEXES = {}
    
    def initialize(queue_name, opts={})
      super(queue_name, opts)

      # Even though putting these Mutexes in this hash is, by itself, not particularly threadsafe
      # as long as some Mutex ends up in the queue after all consumers are created we're good
      # as they are pulled from the queue and synchronized for file operations below
      FILE_QUEUE_MUTEXES[@queue_name] ||= Mutex.new

      @in_progress_dir = in_progress_dir(queue_name)
      @new_dir = new_dir(queue_name)
    end

    def consume(&handler)
      Chore.logger.info "Starting consuming file system queue #{@queue_name} in #{queue_dir(queue_name)}"
      while running?
        begin
          #TODO move expired job files to new directory?
          handle_jobs(&handler)
        rescue => e
          Chore.logger.error { "#{self.class}#consume: #{e} #{e.backtrace * "\n"}" }
        ensure
          sleep 5
        end
      end
    end

    def reject(id)
      Chore.logger.debug "Rejecting: #{id}"
      make_new_again(id)
    end

    def complete(id)
      Chore.logger.debug "Completing (deleting): #{id}"
      FileUtils.rm(File.join(@in_progress_dir, id))
    end

    private

    # finds all new job files, moves them to in progress and starts the job
    # Returns a list of the job files processed
    def handle_jobs(&block)
      # all consumers on a single queue share a lock on handling files.
      # Each consumer comes along, processes all present files and release the lock.
      # This isn't particularly useful but is here to allow the configuration of
      # ThreadedConsumerStrategy with mutiple threads on a queue safely although you
      # probably wouldn't want to do that.
      FILE_QUEUE_MUTEXES[@queue_name].synchronize do
        job_files.each do |job_file|
          Chore.logger.debug "Found a new job #{job_file}"
          
          job_json = File.read(make_in_progress(job_file))

          # job_file is just the name which is the job id
          block.call(job_file, job_json)
          Chore.run_hooks_for(:on_fetch, job_file, job_json)
        end
      end
    end

    def make_in_progress(job)
      move_job(job, @new_dir, @in_progress_dir)
    end

    def make_new_again(job)
      move_job(job, @in_progress_dir, @new_dir)
    end
    
    # moves job file to inprogress directory and returns the full path
    def move_job(job, from, to)
      f = File.open(File.join(from, job), "r")
      # wait on the lock a publisher in another process might have.
      # Once we get the lock the file is ours to move to mark it in progress
      f.flock(File::LOCK_EX)
      begin
        FileUtils.mv(f.path, to)
      ensure
        f.flock(File::LOCK_UN) # yes we can unlock it after its been moved, I checked
      end
      File.join(to, job)
    end

    def job_files
      Dir.entries(@new_dir).select{|e| ! e.start_with?(".")}
    end
  end
end

