require 'pipe_listener'

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
      Chore.run_hooks_for(:before_first_fork)
    end

    def start
      @listener.start
    end

    def stop!
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
        watch_proc(pid)
      end
    end

    # This is our own implementation of Process.detach, that lets us clean up
    # the worker list first
    def watch_proc(pid)
      thread do
        Process.wait2(pid)
        Chore.logger.debug { "Removed finished worker #{pid}"}
        workers.delete(pid)
      end
    end

    # Only call this in the forked child. It resets some things that need fixing up
    # in the child.
    def after_fork(worker)
      # We blow away the INT handler from the parent process
      trap "INT" do;end;
      # Register a new TERM handler to make the current worker
      # finish this job, and not complete another one. 
      # TODO: Figure out an overall flow of signals such that we
      # can use QUIT here instead of TERM.
      trap "TERM" do
        Chore.logger.info { "Worker #{Process.pid} stopping" }
        worker.stop!
      end
      
      # Replace the stats instance in the child with one that can handle talking over
      # the pipe
      Chore.stats = PipedStats.new(worker.object_id,@listener)
    end

    def workers_available?
      workers.length < Chore.config.num_workers
    end

    # Wrapper around fork for specs.
    def fork(&block)
      Kernel.fork(&block)
    end

    # Wrapper around Thread.new for specs
    def thread(&block)
      Thread.new(&block)
    end

    def procline(str)
      Chore.logger.info str
      $0 = "chore-#{Chore::VERSION}:#{str}"
    end

  end
end
