require 'chore/pipe_listener'

module Chore
  class StatListener < PipeListener
    def handle_payload(payload)
      Chore.logger.debug { "StatListener#handle_payload : #{Base64.encode64(payload)}" }
      data = Marshal.load(payload)
      Chore.stats.add(data[0],data[1])
      data = nil
    rescue => e
      Chore.logger.error { "Failed to unmarshal data from pipe: #{e.inspect} : #{Base64.encode64(payload)}" }
    end
  end

  class PipedStats < Stats
    def initialize(pipe_id,listener,bucket_size=nil)
      super(bucket_size)
      @pipe_id, @listener = pipe_id, listener
    end

    def add(stat,type=:global,data=nil)
      @listener.pipes[@pipe_id].write [stat,StatEntry.new(type,data)]
    end
  end

  class ForkedWorkerStrategy
    attr_accessor :workers

    def initialize(manager)
      @manager = manager
      @workers = {}
      @listener = StatListener.new(60)

      trap_master_signals

      Chore.run_hooks_for(:before_first_fork)
    end

    def start
      @listener.start
    end

    def stop!
      Chore.logger.info { "Worker #{Process.pid} stopping" }
      @workers.keys.each do |pid|
        begin
          Chore.logger.info { "Sending TERM to: #{pid}" }
          Process.kill("SIGTERM", pid)
        rescue Errno::SRCH
        end
      end
      begin
        Timeout::timeout(60) do
          Process.waitall
        end
      rescue Timeout::Error
        Chore.logger.error "Timed out waiting for children to terminate."
      end
      @listener.close_all
    end

    def assign(work)
      if workers_available?
        w = Worker.new(work)
        Chore.run_hooks_for(:before_fork,w)
        @listener.add_pipe(w.object_id)
        pid = fork do
          after_fork(w)

          Chore.run_hooks_for(:after_fork)
          procline("Started:#{Time.now}")
          w.start
          @listener.end_pipe(w.object_id)
          Chore.logger.info("Finished:#{Time.now}")
        end
        Chore.logger.debug { "Forked worker #{pid}"}
        workers[pid] = w
      end
    end

    def trap_master_signals
      trap('CHLD') { reap_terminated_workers }
    end

    def trap_child_signals
      # Register a new TERM handler to make the current worker
      # finish this job, and not complete another one.
      # TODO: Figure out an overall flow of signals such that we
      # can use QUIT here instead of TERM.
      trap("TERM") { worker.stop! }
    end

    def clear_child_signals
      # Remove handlers from the parent process
      trap "INT",  "DEFAULT"
      trap "CHLD", "DEFAULT"
    end

    # Only call this in the forked child. It resets some things that need fixing up
    # in the child.
    def after_fork(worker)
      clear_child_signals
      trap_child_signals

      # Replace the stats instance in the child with one that can handle talking over
      # the pipe
      Chore.stats = PipedStats.new(worker.object_id,@listener)
    end

    def reap_terminated_workers
      # Avoid a SIGCHLD race condition by reaping all available child processes
      while pid = Process.wait(-1, Process::WNOHANG)
        workers.delete(pid)
        Chore.logger.debug { "Removed finished worker #{pid}"}
      end
    rescue Errno::ECHILD
      # Child processes have already terminated
    end

    def workers_available?
      workers.length < Chore.config.num_workers
    end

    # Wrapper around fork for specs.
    def fork(&block)
      Kernel.fork(&block)
    end

    def procline(str)
      Chore.logger.info str
      $0 = "chore-#{Chore::VERSION}:#{str}"
    end

  end
end
