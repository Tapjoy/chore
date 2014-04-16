require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::Signal do
  after(:each) do
    described_class.reset
  end

  describe 'trap' do
    context 'without any handlers' do
      it 'should not raise an error' do
        lambda { Process.kill('WINCH', Process.pid) }.should_not raise_error(Exception)
      end
    end

    context 'with a command' do
      before(:each) do
        described_class.trap('WINCH', 'DEFAULT')
      end

      it 'should not raise an error' do
        lambda { Process.kill('WINCH', Process.pid) }.should_not raise_error(Exception)
      end
    end

    context 'with a command and handler' do
      before(:each) do
        @callbacks = []
        described_class.trap('WINCH', 'DEFAULT') do
          @callbacks << :winch
        end
      end

      it 'should not raise an error' do
        lambda { Process.kill('WINCH', Process.pid) }.should_not raise_error(Exception)
      end

      it 'should not call the handler' do
        Process.kill('WINCH', Process.pid)
        @callbacks.should == []
      end
    end

    context 'with a single handler' do
      before(:each) do
        @callbacks = []
      end

      context 'without exceptions' do
        before(:each) do
          described_class.trap('WINCH') do
            @callbacks << :winch
          end
        end

        it 'should not call the handler if signal does not match' do
          lambda { Process.kill('USR2', Process.pid) }.should raise_error(SignalException)
          @callbacks.should == []
        end

        it 'should call the handler if the signal matches' do
          Process.kill('WINCH', Process.pid)
          @callbacks.should == [:winch]
        end
      end

      context 'with exceptions' do
        before(:each) do
          @count = 0
          @callbacks = []
          described_class.trap('WINCH') do
            @count += 1
            raise ArgumentError if @count == 1
            @callbacks << :winch
          end
        end

        it 'should not retry the callback' do
          Process.kill('WINCH', Process.pid)
          @callbacks.should == []
        end

        it 'should still continue processing' do
          2.times { Process.kill('WINCH', Process.pid) }
          @callbacks.should == [:winch]
        end
      end
    end

    context 'with multiple handlers' do
      before(:each) do
        @callbacks = []
        described_class.trap('WINCH') do
          @callbacks << :first
        end
        described_class.trap('WINCH') do
          @callbacks << :second
        end
      end

      it 'should only call the last recorded handler' do
        Process.kill('WINCH', Process.pid)
        @callbacks.should == [:second]
      end
    end

    context 'with reset handler' do
      before(:each) do
        @callbacks = []
        described_class.trap('WINCH') do
          @callbacks << :first
        end
        described_class.trap('WINCH', 'DEFAULT')
      end

      it 'should not call the original handler' do
        Process.kill('WINCH', Process.pid)
        @callbacks.should == []
      end
    end

    context 'with multiple signals' do
      before(:each) do
        @callbacks = []
        described_class.trap('WINCH') do
          @callbacks << :winch
        end
        described_class.trap('USR2') do
          @callbacks << :usr2
        end
      end

      it 'should handle each one' do
        Process.kill('WINCH', Process.pid)
        Process.kill('USR2', Process.pid)
        @callbacks.should == [:winch, :usr2]
      end

      it 'should process most recent signals first' do
        mutex = Mutex.new
        described_class.trap('WINCH') do
          @callbacks << :winch
          mutex.lock
        end
        described_class.trap('PIPE') do
          @callbacks << :pipe
        end

        mutex.lock
        Process.kill('WINCH', Process.pid)
        Process.kill('WINCH', Process.pid)
        Process.kill('USR2', Process.pid)
        Process.kill('PIPE', Process.pid)
        mutex.unlock
        sleep 1

        @callbacks.should == [:winch, :pipe, :usr2, :winch]
      end

      it 'should process primary signals first' do
        mutex = Mutex.new
        described_class.trap('WINCH') do
          @callbacks << :winch
          mutex.lock
        end
        described_class.trap('CHLD') do
          @callbacks << :chld
        end

        mutex.lock
        Process.kill('WINCH', Process.pid)
        Process.kill('USR2', Process.pid)
        Process.kill('CHLD', Process.pid)
        mutex.unlock
        sleep 1

        @callbacks.should == [:winch, :usr2, :chld]
      end
    end
  end

  describe 'reset' do
    it 'should clear existing handlers' do
      callbacks = []
      described_class.trap('WINCH') do
        callbacks << :winch
      end
      described_class.reset
      Process.kill('WINCH', Process.pid)
      callbacks.should == []
    end

    it 'should not run unprocessed signals' do
      callbacks = []
      described_class.trap('WINCH') do
        callbacks << :winch
        sleep 0.5
      end
      described_class.trap('USR2') do
        callbacks << :usr2
      end
      Process.kill('WINCH', Process.pid)
      Process.kill('USR2', Process.pid)
      described_class.reset
      sleep 1
      callbacks.should == [:winch]
    end

    it 'should still listen for new traps' do
      callbacks = []
      described_class.trap('WINCH') do
        callbacks << :winch
      end
      described_class.reset
      described_class.trap('WINCH') do
        callbacks << :winch
      end
      Process.kill('WINCH', Process.pid)
      callbacks.should == [:winch]
    end
  end
end