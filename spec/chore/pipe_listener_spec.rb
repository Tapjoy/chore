require 'spec_helper'
require 'securerandom'

describe Chore::Pipe do
  let(:pipe) { Chore::Pipe.new }

  it 'should create an IO#pipe on initialize' do
    pipe.in.should be_kind_of IO
    pipe.out.should be_kind_of IO
  end

  it 'should create an open IO#pipe on initialize' do
    pipe.in.should_not be_closed
    pipe.out.should_not be_closed
  end

  it 'should close the write end on read' do
    pipe.in << "asdf\n\n"
    pipe.read.strip.should == 'asdf'
    pipe.in.should be_closed
  end

  it 'should close the read end on write' do
    pipe.write "asdf"
    pipe.out.should be_closed
  end

  after(:each) { pipe.close }
end

describe Chore::PipeListener do
  let(:timeout) { 60 }
  let(:listener) { Chore::PipeListener.new(timeout) }
  let(:id) { SecureRandom.uuid }

  context '#add_pipe' do
    it 'should add to the pipes hash' do
      listener.add_pipe(id)
      listener.pipes[id].should be_kind_of Chore::Pipe
    end

    it 'should wake up the wait loop' do
      listener.should_receive(:wake_up!)
      listener.add_pipe(id)
    end
  end

  context '#end_pipe' do
    it 'should put an "EOF" on the pipe' do
      listener.add_pipe(id)
      listener.end_pipe(id)
      listener.pipes[id].read.should == 'EOF'
    end
  end

  context '#start' do
    before(:each) { listener.start }

    it 'should wake up when a new pipe is added' do
      listener.signal.out.should_receive(:read).with(1).at_least(:once)
      listener.add_pipe(id)
    end

    it 'should close a pipe when EOF is received' do
      listener.add_pipe(id)
      pid = fork do
        listener.pipes[id].write("EOF")
      end
      Process.wait(pid)
      listener.stop
      listener.pipes[id].should be_closed
    end
    
    it 'should process a message' do
      # This is gross, but marshalling across a pipe changes it to UTF8 and I don't want
      # un marshal it for this test, so, i force the encoding here for a simpler test
      # except i had to write this comment. so its' really not that simple eh?
      data = "Some Data".force_encoding("UTF-8")
      payload = Marshal.dump(data) + "\n\n"
      listener.add_pipe(id)
      listener.should_receive(:handle_payload).with(payload)
      pid = fork do
        listener.pipes[id].write(data)
      end
      Process.wait(pid)
      listener.stop
    end

    after(:each) { listener.stop }
  end

  after(:each) { listener.close_all }
end
