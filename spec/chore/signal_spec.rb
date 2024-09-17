require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::Signal do
  let(:signal_handlers) {{}}
  before :each do
    allow(::Signal).to receive(:trap) do |signal, command=nil, &block|
      if command
        signal_handlers.delete(signal)
      else
        signal_handlers[signal] = block
      end
    end

    allow(Process).to receive(:kill) do |signal, process_id|
      signal_handlers[signal].call if signal_handlers[signal]
      sleep 0.1
    end
  end

  after(:each) do
    described_class.reset
  end

  describe 'trap' do
    context 'without any handlers' do
      it 'should not be intercepted by Chore::Signal' do
        expect(described_class).not_to receive(:process).with("SIG1")
        lambda { Process.kill('SIG1', Process.pid) }
      end
    end

    context 'with a command' do
      before(:each) do
        described_class.trap('SIG1', 'DEFAULT')
      end

      it 'should result in Rubys default behavior for the signal' do
        expect { Process.kill('SIG1', Process.pid) }.not_to raise_error
      end
    end

    context 'with a command and handler' do
      before(:each) do
        @callbacks = []
        described_class.trap('SIG1', 'DEFAULT') do
          @callbacks << :usr2
        end
      end

      it 'should result in Rubys default behavior for the signal' do
        expect { Process.kill('SIG1', Process.pid) }.not_to raise_error
      end

      it 'should not call the handler' do
        begin
          Process.kill('SIG1', Process.pid)
        rescue SignalException => e

        end
        expect(@callbacks).to match_array([])
      end
    end

    context 'with a single handler' do
      before(:each) do
        @callbacks = []
      end

      context 'without exceptions' do
        before(:each) do
          described_class.trap('SIG1') do
            @callbacks << :sig1
          end
        end

        it 'should not call the handler if signal does not match' do
          expect { Process.kill('SIG2', Process.pid) }.not_to raise_error
          expect(@callbacks).to match_array([])
        end

        it 'should call the handler if the signal matches' do
          Process.kill('SIG1', Process.pid)
          expect(@callbacks).to match_array([:sig1])
        end
      end

      context 'with exceptions' do
        before(:each) do
          @count = 0
          @callbacks = []
          described_class.trap('SIG1') do
            @count += 1
            raise ArgumentError if @count == 1
            @callbacks << :sig1
          end
        end

        it 'should not retry the callback' do
          Process.kill('SIG1', Process.pid)
          expect(@callbacks).to match_array([])
        end

        it 'should still continue processing' do
          2.times { Process.kill('SIG1', Process.pid) }
          expect(@callbacks).to match_array([:sig1])
        end
      end
    end

    context 'with multiple handlers' do
      before(:each) do
        @callbacks = []
        described_class.trap('SIG1') do
          @callbacks << :first
        end
        described_class.trap('SIG1') do
          @callbacks << :second
        end
      end

      it 'should only call the last recorded handler' do
        Process.kill('SIG1', Process.pid)
        expect(@callbacks).to match_array([:second])
      end
    end

    context 'with reset handler' do
      before(:each) do
        @callbacks = []
        described_class.trap('SIG1') do
          @callbacks << :first
        end
        described_class.trap('SIG1', 'DEFAULT')
      end

      it 'should not call the original handler' do
        Process.kill('SIG1', Process.pid)
        expect(@callbacks).to match_array([])
      end
    end

    context 'with multiple signals' do
      before(:each) do
        @callbacks = []
        described_class.trap('SIG1') do
          @callbacks << :sig1
        end
        described_class.trap('SIG2') do
          @callbacks << :sig2
        end
      end

      it 'should handle each one' do
        Process.kill('SIG1', Process.pid)
        Process.kill('SIG2', Process.pid)
        expect(@callbacks).to match_array([:sig1, :sig2])
      end

      it 'should process most recent signals first' do
        mutex = Mutex.new
        described_class.trap('SIG1') do
          @callbacks << :sig1
          mutex.lock
        end
        described_class.trap('SIG3') do
          @callbacks << :sig3
        end

        mutex.lock
        Process.kill('SIG1', Process.pid)
        Process.kill('SIG1', Process.pid)
        Process.kill('SIG2', Process.pid)
        Process.kill('SIG3', Process.pid)
        mutex.unlock
        sleep 0.1

        expect(@callbacks).to match_array([:sig1, :sig3, :sig2, :sig1])
      end

      it 'should process primary signals first' do
        mutex = Mutex.new
        described_class.trap('SIG1') do
          @callbacks << :sig1
          mutex.lock
        end
        described_class.trap('SIG3') do
          @callbacks << :sig3
        end

        mutex.lock
        Process.kill('SIG1', Process.pid)
        Process.kill('SIG2', Process.pid)
        Process.kill('SIG3', Process.pid)
        mutex.unlock
        sleep 0.1

        expect(@callbacks).to match_array([:sig1, :sig2, :sig3])
      end
    end
  end

  describe 'reset' do
    it 'should clear existing handlers' do
      callbacks = []
      described_class.trap('SIG1') do
        callbacks << :sig1
      end
      described_class.reset
      Process.kill('SIG1', Process.pid)
      expect(callbacks).to match_array([])
    end

    it 'should not run unprocessed signals' do
      callbacks = []
      mutex = Mutex.new
      described_class.trap('SIG1') do
        callbacks << :sig1
        mutex.lock
      end
      described_class.trap('SIG2') do
        callbacks << :sig2
      end
      mutex.lock
      Process.kill('SIG1', Process.pid)
      Process.kill('SIG2', Process.pid)
      described_class.reset
      mutex.unlock
      expect(callbacks).to match_array([:sig1])
    end

    it 'should still listen for new traps' do
      callbacks = []
      described_class.trap('SIG1') do
        callbacks << :sig1
      end
      described_class.reset
      described_class.trap('SIG1') do
        callbacks << :sig1
      end
      Process.kill('SIG1', Process.pid)
      expect(callbacks).to match_array([:sig1])
    end
  end
end
