require 'fileutils'
require 'chore/queues/filesystem/filesystem_queue'

module Chore
  module Queues
    module Filesystem

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
      class Consumer < Chore::Consumer
        extend FilesystemQueue

        Chore::CLI.register_option 'fs_queue_root', '--fs-queue-root DIRECTORY', 'Root directory for fs based queue'
        
        FILE_QUEUE_MUTEXES = {}

        class << self
          # Cleans up the in-progress files by making them new again.  This should only
          # happen once per process.
          def cleanup(queue)
            new_dir = self.new_dir(queue)
            in_progress_dir = self.in_progress_dir(queue)

            each_job_file(in_progress_dir) do |file|
              make_new_again(file, new_dir, in_progress_dir)
            end
          end

          def make_in_progress(job, new_dir, in_progress_dir)
            move_job(File.join(new_dir, job), File.join(in_progress_dir, job))
          end

          def make_new_again(job, new_dir, in_progress_dir)
            basename, previous_attempts = file_info(job)
            move_job(File.join(in_progress_dir, job), File.join(new_dir, "#{basename}.#{previous_attempts + 1}.job"))
          end

          # Moves job file to inprogress directory and returns the full path
          def move_job(from, to)
            File.open(from, "r") do |f|
              # wait on the lock a publisher in another process might have.
              # Once we get the lock the file is ours to move to mark it in progress
              f.flock(File::LOCK_EX)
              FileUtils.mv(f.path, to)
            end

            to
          end

          def each_job_file(dir, limit = nil)
            count = 0

            Dir.foreach(dir) do |file|
              next if file.start_with?('.')

              yield file

              count += 1
              break if limit && count >= limit
            end
          end

          # Grabs the unique identifier for the job filename and the number of times
          # it's been attempted (also based on the filename)
          def file_info(job_file)
            id, previous_attempts = File.basename(job_file, '.job').split('.')
            [id, previous_attempts.to_i]
          end
        end

        # The amount of time units of work can run before the queue considers
        # them timed out.  For filesystem queues, this is the global default.
        attr_reader :queue_timeout

        def initialize(queue_name, opts={})
          super(queue_name, opts)

          # Even though putting these Mutexes in this hash is, by itself, not particularly threadsafe
          # as long as some Mutex ends up in the queue after all consumers are created we're good
          # as they are pulled from the queue and synchronized for file operations below
          FILE_QUEUE_MUTEXES[@queue_name] ||= Mutex.new

          @in_progress_dir = self.class.in_progress_dir(queue_name)
          @new_dir = self.class.new_dir(queue_name)
          @queue_timeout = Chore.config.default_queue_timeout
        end

        def consume
          Chore.logger.info "Starting consuming file system queue #{@queue_name} in #{self.class.queue_dir(queue_name)}"
          while running?
            begin
              #TODO move expired job files to new directory?
              found_files = false
              handle_jobs do |*args|
                found_files = true
                yield(*args)
              end
            rescue => e
              Chore.logger.error { "#{self.class}#consume: #{e} #{e.backtrace * "\n"}" }
            ensure
              sleep(Chore.config.consumer_sleep_interval) unless found_files
            end
          end
        end

        def reject(id)
          Chore.logger.debug "Rejecting: #{id}"
          make_new_again(id)
        end

        def complete(id)
          Chore.logger.debug "Completing (deleting): #{id}"
          FileUtils.rm_f(File.join(@in_progress_dir, id))
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
            self.class.each_job_file(@new_dir, Chore.config.queue_polling_size) do |job_file|
              Chore.logger.debug "Found a new job #{job_file}"

              job_json = File.read(make_in_progress(job_file))
              basename, previous_attempts = self.class.file_info(job_file)

              # job_file is just the name which is the job id
              block.call(job_file, queue_name, queue_timeout, job_json, previous_attempts)
              Chore.run_hooks_for(:on_fetch, job_file, job_json)
            end
          end
        end

        def make_in_progress(job)
          self.class.make_in_progress(job, @new_dir, @in_progress_dir)
        end

        def make_new_again(job)
          self.class.make_new_again(job, @new_dir, @in_progress_dir)
        end
      end
    end
  end
end

