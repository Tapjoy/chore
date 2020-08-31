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

        class << self
          # Cleans up expired in-progress files by making them new again.
          def cleanup(expiration_time, new_dir, in_progress_dir)
            each_file(in_progress_dir) do |job_file|
              id, previous_attempts, timestamp = file_info(job_file)
              next if timestamp > expiration_time

              begin
                make_new_again(job_file, new_dir, in_progress_dir)
              rescue Errno::ENOENT
                # File no longer exists; skip since it's been recovered by another
                # consumer
              rescue ArgumentError
                # Move operation was attempted at same time as another consumer;
                # skip since the other process succeeded where this one didn't
              end
            end
          end

          # Moves job file to inprogress directory and returns the full path
          # if the job was successfully locked by this consumer
          def make_in_progress(job, new_dir, in_progress_dir, queue_timeout)
            basename, previous_attempts, * = file_info(job)

            from = File.join(new_dir, job)
            # Add a timestamp to mark when the job was started
            to = File.join(in_progress_dir, "#{basename}.#{previous_attempts}.#{Time.now.to_i}.job")

            # If the file is non-zero, this means it was successfully written to
            # by a publisher and we can attempt to move it to "in progress".
            #
            # There is a small window of time where the file can be zero, but
            # the publisher hasn't finished writing to the file yet.
            if !File.zero?(from)
              File.open(from, "r") do |f|
                # If the lock can't be obtained, that means it's been locked
                # by another consumer or the publisher of the file) -- don't
                # block and skip it
                if f.flock(File::LOCK_EX | File::LOCK_NB)
                  FileUtils.mv(from, to)
                  to
                end
              end
            elsif (Time.now - File.ctime(from)) >= queue_timeout
              # The file is empty (zero bytes) and enough time has passed since
              # the file was written that we can safely assume it will never
              # get written to be the publisher.
              #
              # The scenario where this happens is when the publisher created
              # the file, but the process was killed before it had a chance to
              # actually write the data.
              File.delete(from)
              nil
            end
          rescue Errno::ENOENT
            # File no longer exists; skip it since it's been picked up by
            # another consumer
          end

          # Moves job file to new directory and returns the full path
          def make_new_again(job, new_dir, in_progress_dir)
            basename, previous_attempts = file_info(job)

            from = File.join(in_progress_dir, job)
            to = File.join(new_dir, "#{basename}.#{previous_attempts + 1}.job")
            FileUtils.mv(from, to)

            to
          end

          def each_file(path, limit = nil)
            count = 0

            Dir.foreach(path) do |file|
              next if file.start_with?('.')

              yield file

              count += 1
              break if limit && count >= limit
            end
          end

          # Grabs the unique identifier for the job filename and the number of times
          # it's been attempted (also based on the filename)
          def file_info(job_file)
            id, previous_attempts, timestamp, * = job_file.split('.')
            [id, previous_attempts.to_i, timestamp.to_i]
          end
        end

        # The minimum number of seconds to allow to pass between checks for expired
        # jobs on the filesystem.
        #
        # Since queue times are measured on the order of seconds, 1 second is the
        # smallest duration.  It also prevents us from burning a lot of CPU looking
        # at expired jobs when the consumer sleep interval is less than 1 second.
        EXPIRATION_CHECK_INTERVAL = 1

        # The amount of time units of work can run before the queue considers
        # them timed out.  For filesystem queues, this is the global default.
        attr_reader :queue_timeout

        def initialize(queue_name, opts={})
          super(queue_name, opts)

          @in_progress_dir = self.class.in_progress_dir(queue_name)
          @new_dir = self.class.new_dir(queue_name)
          @queue_timeout = self.class.queue_timeout(queue_name)
        end

        def consume
          Chore.logger.info "Starting consuming file system queue #{@queue_name} in #{self.class.queue_dir(queue_name)}"
          while running?
            begin
              # Move expired job files to new directory (so long as enough time has
              # passed since we last did this check)
              if !@last_cleaned_at || (Time.now - @last_cleaned_at).to_i >= EXPIRATION_CHECK_INTERVAL
                self.class.cleanup(Time.now.to_i - @queue_timeout, @new_dir, @in_progress_dir)
                @last_cleaned_at = Time.now
              end

              found_files = false
              handle_messages do |*args|
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

        # Rejects the given message from the filesystem by +id+. Currently a noop
        def reject(id)

        end

        # Deletes the given message from filesystem queue. Since the filesystem is not a remote API, there is no
        # notion of a "receipt handle".
        #
        # @param [String] message_id Unique ID of the message
        # @param [Hash] receipt_handle Receipt handle of the message. Always nil for the filesystem consumer
        def complete(message_id, receipt_handle = nil)
          Chore.logger.debug "Completing (deleting): #{message_id}"
          File.delete(File.join(@in_progress_dir, message_id))
        rescue Errno::ENOENT
          # The job took too long to complete, was deemed expired, and moved
          # back into "new".  Ignore.
        end

        private

        # finds all new job files, moves them to in progress and starts the job
        # Returns a list of the job files processed
        def handle_messages(&block)
          self.class.each_file(@new_dir, Chore.config.queue_polling_size) do |job_file|
            Chore.logger.debug "Found a new job #{job_file}"

            in_progress_path = make_in_progress(job_file)
            next unless in_progress_path

            # The job filename may have changed, so update it to reflect the in progress path
            job_file = File.basename(in_progress_path)

            job_json = File.read(in_progress_path)
            basename, previous_attempts, * = self.class.file_info(job_file)

            # job_file is just the name which is the job id. 2nd argument (:receipt_handle) is nil because the
            # filesystem is dealt with directly, as opposed to being an external API
            block.call(job_file, nil, queue_name, queue_timeout, job_json, previous_attempts)
            Chore.run_hooks_for(:on_fetch, job_file, job_json)
          end
        end

        def make_in_progress(job)
          self.class.make_in_progress(job, @new_dir, @in_progress_dir, @queue_timeout)
        end

        def make_new_again(job)
          self.class.make_new_again(job, @new_dir, @in_progress_dir)
        end
      end
    end
  end
end
