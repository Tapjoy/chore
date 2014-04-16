module Chore
  # Provides smarter signal handling capabilities than Ruby's built-in
  # Signal class.  Specifically it runs callbacks in a separate thread since:
  #   (1) Ruby 2.0 cannot obtain locks in the main Signal thread
  #   (2) Doing so can result in deadlocks in Ruby 1.9.x.
  # 
  # Ruby's core implementation can be found at: http://ruby-doc.org/core-1.9.3/Signal.html
  # 
  # == Differences
  # 
  # There are a few important differences with the way signals trapped through
  # this class behave than through Ruby's Signal class.
  # 
  # === Sequential processing
  # 
  # In Ruby, signals are interrupt-driven -- the thread is executing at the time
  # will be interrupted at that point in the call stack and start executing the
  # signal handler.  This increases the potential for deadlocks if mutexes are
  # in use by both the thread and the signal handler.
  # 
  # In Chore, signal handlers are executed sequentially.  When a handler is
  # started, it must complete before the next signal is processed.  These
  # handlers are also executed in their own thread and, therefore, will compete
  # for resources with the rest of the application.
  # 
  # === Forking
  # 
  # In Ruby, forking does not disrupt the ability to process signals.  Signals
  # trapped in the master process will continue to be trapped in forked child
  # processes.
  # 
  # In Chore, this is not the case.  When a process is forked, any trapped
  # signals will no longer get processed.  This is because the thread that
  # processes those incoming signals gets killed.
  # 
  # In order to process these signals, `Chore::Signal.reset` must be called,
  # followed by additional calls to re-register those signal handlers.
  # 
  # == Signal ordering
  # 
  # It is important to note that in Ruby, signals are essentially processed
  # as LIFO (Last-In, First-Out) since they are interrupt driven.  Similar
  # behaviors is present in Chore's implementation.
  # 
  # Having LIFO behavior is the reason why this class uses a queue for
  # tracking the list of incoming signals, instead of writing them out to a
  # pipe.
  class Signal
    # The handlers registered for trapping certain signals.  Maps signal => handler.
    @handlers = {}

    # The set of incoming, unprocessed high-priority signals (such as QUIT / INT)
    @primary_signals = []

    # The set of incoming, unprocessed low-priority signals (such as CHLD)
    @secondary_signals = []

    # The priorities of signals to handle.  If not defined, the signal is
    # considered high-priority.
    PRIORITIES = {
      'CHLD' => :secondary
    }

    # Stream used to track when signals are ready to be processed
    @wake_in, @wake_out = IO.pipe

    class << self
      # Traps the given signal and runs the block when the signal is sent to
      # this process.  This will run the block outside of the trap thread.
      # 
      # Only a single handler can be registered for a signal at any point.  If
      # a signal has already been trapped, a warning will be generated and the
      # previous handler for the signal will be returned.
      # 
      # See ::Signal#trap @ http://ruby-doc.org/core-1.9.3/Signal.html#method-c-trap
      # for more information.
      def trap(signal, command = nil, &block)
        if command
          # Command given for Ruby to interpret -- pass it directly onto Signal
          @handlers.delete(signal)
          ::Signal.trap(signal, command)
        else
          # Ensure we're listening for signals
          listen

          if @handlers[signal]
            Chore.logger.debug "#{signal} signal has been overwritten:\n#{caller * "\n"}"
          end

          # Wrap handlers so they run in the listener thread
          signals = PRIORITIES[signal] == :secondary ? @secondary_signals : @primary_signals
          @handlers[signal] = block
          ::Signal.trap(signal) do
            signals << signal
            wakeup
          end
        end
      end

      # Resets signals and handlers back to their defaults.  Any unprocessed
      # signals will be discarded.
      # 
      # This should be called after forking a processing in order to ensure
      # that signals continue to get processed.  *Note*, however, that new
      # handlers must get registered after forking.
      def reset
        # Reset traps back to their default behavior.  Note that this *must*
        # be done first in order to prevent trap handlers from being called
        # while the wake pipe / listener are being reset.  If this is run
        # out of order, then it's possible for those callbacks to hit errors.
        @handlers.keys.each {|signal| trap(signal, 'DEFAULT')}

        # Reset signals back to their empty state
        @listener = nil
        @primary_signals.clear
        @secondary_signals.clear
        @wake_out.close
        @wake_in.close
        @wake_in, @wake_out = IO.pipe
      end

      private
      # Starts the thread that processes incoming signals
      def listen
        @listener ||= Thread.new do
          on_wakeup do
            while signal = next_signal
              process(signal)
            end
          end
        end
      end

      # Looks up what the next signal is to process.  Signals are typically
      # processed LIFO (Last In, First Out), though primary signals are
      # prioritized over secondary signals.
      def next_signal
        @primary_signals.pop || @secondary_signals.pop
      end

      # Waits until a wakeup signal is received.  When it is received, the
      # provided block will be yielded to.
      def on_wakeup
        begin
          while @wake_in.getc
            yield
          end
        rescue IOError => e
          # Ignore: listener has been stopped
          Chore.logger.debug "Signal stream closed: #{e}\n#{e.backtrace * "\n"}"
        end
      end

      # Wakes up the listener thread to indicate that signals are ready to be
      # processed
      def wakeup
        @wake_out.write('.')
      end

      # Processes the given signal by running the handler in a separate
      # thread.
      def process(signal)
        handler = @handlers[signal]
        if handler
          begin
            handler.call
          rescue => e
            # Prevent signal handlers from killing the listener thread
            Chore.logger.error "Failed to run #{signal} signal handler: #{e}\n#{e.backtrace * "\n"}"
          end
        end
      end
    end
  end
end