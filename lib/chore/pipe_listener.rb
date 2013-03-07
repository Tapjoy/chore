require 'base64'
require 'pry'

module Chore
  class Pipe
    attr_accessor :in, :out

    def initialize
      @out,@in = IO.pipe
    end

    # Does a sane pipe read looking for a Marshal safe separator. Ensures the other end of the pipe is closed. Should not be used from the same process that does the write call.
    def read
      # close the write end if we're on the reading end
      @in.close unless @in.closed?
      # use the paragraph separator, shouldn't conflict with marshalling
      @out.gets("\n\n")
    end

    # Does a sane pipe write with a Marshal safe separator. Ensures the other end of the pipe is closed. Should not be used from the same process that does the read call.
    def write(data)
      # close the read end if we're on the writing end
      @out.close unless @out.closed?
      Chore.logger.debug { "Writing to pipe: #{data.inspect}" }
      begin
        @in << Marshal.dump(data)
        @in << "\n\n"
      rescue Errno::EPIPE => e
        Chore.logger.error { "Can't write to pipe. A process probably went away: #{e.message}" }
      end
    end

    # Close both ends of the pipe
    def close
      @in.close unless @in.closed?
      @out.close unless @out.closed?
    end

    # Is the pipe entirely closed? (Both read and write ends)
    def closed?
      @in.closed? && @out.closed?
    end
  end

  class PipeListener
    attr_accessor :pipes
    attr_accessor :timeout
    attr_accessor :signal

    def initialize(timeout)
      @signal = Pipe.new
      @timeout = timeout
      @pipes = {}
      @stopping = false
    end

    def add_pipe(id)
      @pipes[id] = Pipe.new
      # we need to wake up the listening loop, so it can reload the list of pipes
      wake_up!
      @pipes[id]
    end

    def end_pipe(id)
      @pipes[id].in << "EOF"
    end

    def start
      @thread = Thread.new do
        loop do
          prune!
          # get a list of pipes, include the signal pipe so we can break out of here
          # from the outside
          listen_to = @pipes.map{|k,p| p.out } + [@signal.out]
          # check if any pipes are ready for reading
          if ready = IO.select(listen_to,[],[],@timeout)
            pipe = ready[0][0]
            # don't try to process stuff from the signal pipe, it's just noise to signal
            # us to move on
            if pipe == @signal.out
              pipe.read(1)
              Chore.logger.info { "PipeListener#start Woke up from a signal" }
            else
              # take the actual io::pipe and find our wrapped pipe, then pull the payload
              payload = pipe_from_handle(pipe).read
              Chore.logger.info { "PipeListener#start Woke up from a message: #{pipe.inspect}: #{payload.inspect}" }
              if payload && !payload.empty?
                # if the child tells us it's done, let's be done
                if payload.to_s == 'EOF'
                  pipe_from_handle(pipe).close 
                  remove_pipe(pipe)
                  next
                end
                handle_payload(payload)
              end
            end
          end

          break if should_stop?
        end
      end
    end

    def stop
      return if @stopping
      @stopping = true
      # wait for the thread to finish
      @thread.join 
      close_all
      @signal.close
    end

    def wake_up!
      @signal.in << '.'
    end

    def close_all
      @pipes.each {|k,p| p.close }
      @signal.close
    end

    def prune!
      @pipes.reject! {|k,p| p.out.closed? }
    end

    protected
    def handle_payload(payload)
    end

    def should_stop?
      @stopping
    end

    def pipe_from_handle(handle)
      @pipes.values.find { |p| p.out == handle }
    end

    def remove_pipe(handle)
      @pipes.delete_if {|k,p| p.out == handle }
    end

  end
end
