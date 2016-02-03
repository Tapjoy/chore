require 'spec_helper'

describe Chore::Strategy::PreforkedWorker do
  before(:each) do
    allow_any_instance_of(Chore::Strategy::PreforkedWorker).to receive(:post_fork_setup)
  end
  let(:preforkedworker) { Chore::Strategy::PreforkedWorker.new }
  let(:socket) { double("socket") }
  let(:work) { double("work") }
  let(:consumer) { double("consumer") }
  let(:worker) { double("worker") }
  let(:config) { double("config") }
  let(:consumer_object) { double("consumer_object") }
  let(:signals) { { '1' => 'QUIT' } }

  context '#start_worker' do
    it 'should connect to the master to signal that it is ready, and process messages with the worker' do
      allow(preforkedworker).to receive(:connect_to_master).and_return(socket)
      expect(preforkedworker).to receive(:connect_to_master).with(socket)
      allow(preforkedworker).to receive(:worker).and_return(true)
      expect(preforkedworker).to receive(:worker).with(socket)
      preforkedworker.start_worker(socket)
    end
  end

  describe '#worker' do
    before(:each) do
      preforkedworker.instance_variable_set(:@self_read, socket)
      allow(preforkedworker).to receive(:select_sockets).and_return([[socket],nil,nil])
      allow(preforkedworker).to receive(:read_msg).and_return(nil)
      allow(preforkedworker).to receive(:is_orphan?).and_return(false)
      allow(preforkedworker).to receive(:process_work).and_return(true)
      allow(preforkedworker).to receive(:signal_ready).and_return(true)
      allow(work).to receive(:queue_timeout).and_return(20*60)
    end


    it 'should not run while @running is false' do
      allow(preforkedworker).to receive(:running?).and_return(false)
      expect(preforkedworker).to receive(:select_sockets).exactly(0).times
      begin
        preforkedworker.send(:worker, nil)
      rescue SystemExit=>e
        expect(e.status).to eq(0)
      end
    end

    it 'should be able to handle select timeouts' do
      allow(preforkedworker).to receive(:running?).and_return(true, true, false)
      allow(preforkedworker).to receive(:select_sockets).and_return(nil)
      expect(preforkedworker).to receive(:select_sockets).exactly(1).times
      begin
        preforkedworker.send(:worker, nil)
      rescue SystemExit=>e
        expect(e.status).to eq(0)
      end
    end

    it 'should read a message if the connection is readable' do
      allow(preforkedworker).to receive(:running?).and_return(true, false)
      expect(preforkedworker).to receive(:read_msg).once
      begin
        preforkedworker.send(:worker, nil)
      rescue SystemExit=>e
        expect(e.status).to eq(0)
      end
    end

    it 'should check if the master is alive, and if not, it should end' do
      allow(preforkedworker).to receive(:running).and_return(true)
      allow(preforkedworker).to receive(:select_sockets).and_return([[socket],nil,nil])
      allow(preforkedworker).to receive(:read_msg).and_return(nil)
      allow(preforkedworker).to receive(:is_orphan?).and_return(true)
      begin
        preforkedworker.send(:worker, socket)
      rescue SystemExit=>e
        expect(e.status).to eq(0)
      end
    end

    it 'should process work if it is read from the master and signal ready' do
      allow(preforkedworker).to receive(:running?).and_return(true, false)
      allow(preforkedworker).to receive(:read_msg).and_return(work)
      expect(preforkedworker).to receive(:process_work).once
      expect(preforkedworker).to receive(:signal_ready).once
      begin
        preforkedworker.send(:worker, socket)
      rescue SystemExit=>e
        expect(e.status).to eq(0)
      end
    end
  end

  context '#connect_to_master' do
    it 'should create a connection to the master, and send it its PID and a ready message' do
      allow(preforkedworker).to receive(:child_connection).and_return(socket)
      allow(preforkedworker).to receive(:send_msg).and_return(true)
      allow(preforkedworker).to receive(:signal_ready).and_return(true)

      expect(preforkedworker).to receive(:child_connection).once
      expect(preforkedworker).to receive(:send_msg).once
      expect(preforkedworker).to receive(:signal_ready).once

      res = preforkedworker.send(:connect_to_master,socket)

      expect(res).to eq(socket)
    end
  end

  context '#post_fork_setup' do
    before(:each) do
      allow(preforkedworker).to receive(:procline).and_return(true)
      allow(preforkedworker).to receive(:trap_signals)
      allow_any_instance_of(Chore::Strategy::PreforkedWorker).to receive(:post_fork_setup).and_call_original
    end

    it 'should change the process name' do
      expect(preforkedworker).to receive(:procline)
      preforkedworker.send(:post_fork_setup)
    end

    it 'should trap new relevant signals' do
      expect(preforkedworker).to receive(:trap_signals)
      preforkedworker.send(:post_fork_setup)
    end
  end

  context '#process_work' do
    before(:each) do
      allow(preforkedworker).to receive(:consumer).and_return(consumer)
      allow(work).to receive(:queue_name).and_return("test_queue")
      allow(work).to receive(:consumer=)
      allow(work).to receive(:queue_timeout).and_return(10)
      allow(Chore::Worker).to receive(:new).and_return(worker)
      allow(worker).to receive(:start)
    end

    it 'should fetch the consumer object associated with the queue' do
      expect(preforkedworker).to receive(:consumer)
      preforkedworker.send(:process_work, [work])
    end

    it 'should create and start a worker object with the job sent to it' do
      expect(worker).to receive(:start)
      preforkedworker.send(:process_work, [work])
    end

    it 'should timeout if the work runs for longer than the queue timeout' do
      allow(work).to receive(:queue_timeout).and_return(1)
      allow(worker).to receive(:start) { sleep 5 }
      begin
        preforkedworker.send(:process_work, [work])
      rescue SystemExit=>e
        expect(e.status).to eq(0)
      end
    end
  end

  context '#consumer' do
    before(:each) do
      preforkedworker.instance_variable_set(:@consumer_cache, {key_1: :value_1})
      allow(Chore).to receive(:config).and_return(config)
      allow(config).to receive(:consumer).and_return(consumer)
      allow(consumer).to receive(:new).and_return(:value_2)
    end

    it 'should fetch a consumer object if it was created previously for this queue' do
      res = preforkedworker.send(:consumer,:key_1)
      expect(res).to eq(:value_1)
    end

    it 'should create and return a new consumer object if one does not exist for this queue' do
      expect(consumer).to receive(:new)
      res = preforkedworker.send(:consumer,:key_2)
      expect(res).to eq(:value_2)
    end
  end

  context '#trap_signals' do
    it 'should reset signals' do
      allow(Chore::Signal).to receive(:reset)
      expect(Chore::Signal).to receive(:reset)
      preforkedworker.send(:trap_signals, {})
    end

    it 'should trap the signals passed to it' do
      allow(Chore::Signal).to receive(:reset)
      expect(Chore::Signal).to receive(:trap).with('QUIT').once
      preforkedworker.send(:trap_signals, signals)
    end
  end

  context '#is_orphan?' do
    it 'should return true if the parent is dead' do
      allow(Process).to receive(:ppid).and_return(10)
      preforkedworker.instance_variable_set(:@manager_pid, 9)
      res = preforkedworker.send(:is_orphan?)
      expect(res).to eq(true)
    end

    it 'should return false if the parent is alive' do
      allow(Process).to receive(:ppid).and_return(10)
      preforkedworker.instance_variable_set(:@manager_pid, 10)
      res = preforkedworker.send(:is_orphan?)
      expect(res).to eq(false)
    end
  end
end

