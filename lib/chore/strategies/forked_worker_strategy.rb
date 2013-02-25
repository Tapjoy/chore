module Chore
  class ForkedWorkerStrategy
    attr_accessor :workers

    def initialize(manager)
      @manager = manager
      @workers = {}
    end

    def stop!
      @workers.keys.each do |pid|
        begin
          Chore.logger.info { "Sending TERM to: #{pid}" }
          Process.kill("SIGTERM", pid)
        rescue Errno::ESRCH
        end
      end
    end

    def assign(work)
      if workers_available?
        w = Worker.new
        Chore.logger.debug { "Assigning work to #{w.inspect}"}
        pid = fork do
          # We blow away the INT handler from the parent process
          trap "INT" do;end;
          # Register a new TERM handler to make the current worker
          # finish this job, and not complete another one. 
          # TODO: Figure out an overall flow of signals such that we
          # can use QUIT here instead of TERM.
          trap "TERM" do
            Chore.logger.info { "Worker #{Process.pid} stopping" }
            w.stop!
          end

          Chore.run_hooks_for(:after_fork)
          procline("Started:#{Time.now.to_i}")
          w.start(work)
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

    def workers_available?
      workers.length < Chore.config.num_workers
    end

    # Wrapper around fork for specs.
    def fork(&block)
      Chore.run_hooks_for(:before_fork)
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
