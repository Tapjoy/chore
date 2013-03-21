require 'chore/pipe_listener'

module Chore
  class WorkerListener < PipeListener

    def initialize(parent,timeout)
      super(timeout)
      @parent = parent
    end

    def handle_payload(payload)
      Chore.logger.debug { "StatListener#handle_payload : #{Base64.encode64(payload)}" }
      data = Marshal.load(payload)
      if data['type'] && data['type'] == 'stat'
        Chore.stats.add(data['value'][0],data['value'][1])
      elsif data['type'] && data['type'] == 'status'
        @parent.workers[data['value']['id']].status = data['value']['status']
      end
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
      @listener.pipes[@pipe_id].write({'type' => 'stat', 'value' => [stat,StatEntry.new(type,data)]})
    end

    def set_worker_status(id,*args)
      @listener.pipes[@pipe_id].write({'type' =>'status', 'value' => {'id' => id, 'status' => args}})
    end
  end

  class ForkedWorkerStrategy
    attr_accessor :workers

    def initialize(manager)
      @manager = manager
      @workers = {}
      @listener = WorkerListener.new(self,60)

      trap_master_signals

      Chore.run_hooks_for(:before_first_fork)
    end

    def start
      Chore.logger.debug "Starting up worker strategy: #{self.class.name}"
      @listener.start
    end

    def stop!
      Chore.logger.info { "Worker #{Process.pid} stopping" }
      begin
        signal_children("QUIT")
        Timeout::timeout(60) do
          Process.waitall
        end
      rescue Timeout::Error
        Chore.logger.error "Timed out waiting for children to terminate. Terminating with prejudice."
        signal_children("KILL")
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

    def trap_child_signals(worker)
      # Register a new QUIT handler to make the current worker
      # finish this job, and not complete another one.
      trap("INT") { worker.stop! }
      trap("QUIT") { worker.stop! }
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
      trap_child_signals(worker)

      # Replace the stats instance in the child with one that can handle talking over
      # the pipe
      Chore.stats = PipedStats.new(worker.object_id,@listener)

      # Okay, so we replace status= in the worker to set the status over the pipe. This is
      # pretty rough, but lets us keep the worker from caring that it's forked. 
      class << worker
        def status=(status)
          Chore.stats.set_worker_status(Process.pid,status)
        end
      end
        
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

    def signal_children(sig)
      @workers.keys.each do |pid|
        begin
          Chore.logger.info { "Sending #{sig} to: #{pid}" }
          Process.kill(sig, pid)
        rescue Errno::ESRCH
        end
      end
    end

  end
end
