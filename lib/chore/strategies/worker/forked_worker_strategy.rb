require 'chore/pipe_listener'

module Chore
  module Strategy
    class WorkerListener < PipeListener
      # The WorkerListener is a particular implementation of the PipeListener. It's modeled after NewRelic's method of shuttling
      # data between processes. We use it for a similar purpose. It's primarily used to transfer data from
      # child processes to the master for tracking stats on the internal stat server.

      def initialize(parent,timeout)
        super(timeout)
        @parent = parent
      end

      # <tt>handle_payload</tt> is called in the master process for each message that comes across the pipe.
      # It unmarshals the +payload+ into a simple hash structure.
      #    { 'type' => 'stat', 'value' => [key,val] }
      # It then takes that data and passes it along to Chore.stats.add.
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
      # PipedStats is a neat trick to avoid having to let our Worker know whether or not it's running forked.
      # After we fork a child, we reset Chore.stats to be an instance of PipedStats. This class overrides a couple
      # of key methods to send data across the pipe, instead of directly into the in memory stats. 
      def initialize(pipe_id,listener,bucket_size=nil)
        super(bucket_size)
        @pipe_id, @listener = pipe_id, listener
      end

      # Override <tt>add</tt> to write data to the pipe instead of directly into memory. This let's us track stats 
      # globally, even from forked workers.
      def add(stat,type=:global,data=nil)
        @listener.pipes[@pipe_id].write({'type' => 'stat', 'value' => [stat,StatEntry.new(type,data)]})
      end

      # Override <tt>set_worker_status</tt> to write data to the pipe  instead of directly into memory.
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

      # Start up the worker strategy. In this particular case, what we're doing
      # is starting up a WorkerListener, so we can talk to the children.
      def start
        Chore.logger.debug "Starting up worker strategy: #{self.class.name}"
        @listener.start
      end

      # Stop the workers. The particulars of the implementation here are that we
      # send a QUIT signal to each child, wait one minute for it to finish the last job
      # it was working on. If it times out, then we send KILL. In an ideal world this means
      # that <tt>stop!</tt> is non-destructive in that it allow each worker to complete it's
      # current job before dying.
      def stop!
        Chore.logger.info { "Manager #{Process.pid} stopping" }
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

      # Take a UnitOfWork (or an Array of UnitOfWork) and assign it to a Worker. We only
      # assign work if there are <tt>workers_available?</tt>.
      def assign(work)
        if workers_available?
          w = Worker.new(work)
          Chore.run_hooks_for(:before_fork,w)
          @listener.add_pipe(w.object_id)
          pid = fork do
            after_fork(w)

            Chore.run_hooks_for(:after_fork,w)
            procline("Started:#{Time.now}")
            w.start
            @listener.end_pipe(w.object_id)
            Chore.logger.info("Finished:#{Time.now}")
          end
          Chore.logger.debug { "Forked worker #{pid}"}
          workers[pid] = w
        end
      end

      
      def workers_available?
        workers.length < Chore.config.num_workers
      end

      private

      def trap_master_signals
        trap('CHLD') { reap_terminated_workers! }
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

      def reap_terminated_workers!
        # Avoid a SIGCHLD race condition by reaping all available child processes
        while pid = Process.wait(-1, Process::WNOHANG)
          workers.delete(pid)
          Chore.logger.debug { "Removed finished worker #{pid}"}
        end
      rescue Errno::ECHILD
        # Child processes have already terminated
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
end
