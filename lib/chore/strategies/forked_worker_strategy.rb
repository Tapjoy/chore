module Chore
  class ForkedWorkerStrategy
    attr_accessor :workers

    def initialize(manager)
      @manager = manager
      @workers = {}
    end

    def assign(work)
      if workers_available?
        w = Worker.new
        pid = fork do
          procline("Started:#{Time.now.to_i}")
          w.start(work)
        end
        workers[pid] = w
        watch_proc(pid)
      end
    end

    # This is our own implementation of Process.detach, that lets us clean up
    # the worker list first
    def watch_proc(pid)
      thread do
        Process.wait2(pid)
        workers.delete(pid)
      end
    end

    def workers_available?
      workers.length < Chore.config.num_workers
    end

    # Wrapper around fork for specs.
    def fork(&block)
      Kernel.fork(&block)
    end

    def thread(&block)
      Thread.new(&block)
    end

    def procline(str)
      puts str
      $0 = "chore-#{Chore::VERSION}:#{str}"
    end
  end
end
