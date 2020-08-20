require 'spec_helper'

describe Chore::Strategy::PreForkedWorkerStrategy do
  let(:manager) { double('manager') }
  let(:socket)  { double('socket') }
  let(:pipe)    { double('pipe') }
  let(:worker)  { double('worker') }
  let(:worker_manager)   { Chore::Strategy::WorkerManager.new(socket) }
  let(:strategy)         { Chore::Strategy::PreForkedWorkerStrategy.new(manager) }
  let(:work_distributor) { Chore::Strategy::WorkDistributor }

  before(:each) do
    allow_any_instance_of(Chore::Strategy::PreForkedWorkerStrategy).to receive(:trap_signals).and_return(true)
    strategy.instance_variable_set(:@worker_manager, worker_manager)
  end

  context '#start' do
    it 'should create, attach workers and start the worker manager' do
      allow(worker_manager).to receive(:create_and_attach_workers)
      allow(strategy).to receive(:worker_assignment_thread).and_return(true)

      expect(worker_manager).to receive(:create_and_attach_workers)
      expect(strategy).to receive(:worker_assignment_thread)
      strategy.start
    end
  end

  context '#stop!' do
    it 'should set the system\'s running state to false' do
      strategy.instance_variable_set(:@running, true)
      strategy.stop!
      expect(strategy.instance_variable_get(:@running)).to eq false
    end
  end

  context '#worker_assignment_thread' do
    before(:each) do
      allow(Thread).to receive(:new).and_return(true)
    end

    it 'create a new thread with the worker_assignment_loop' do
      allow(strategy).to receive(:worker_assignment_loop).and_return(true)
      expect(Thread).to receive(:new).once.and_yield
      expect(strategy).to receive(:worker_assignment_loop)
      expect(Process).to receive(:exit)
      strategy.send(:worker_assignment_thread)
    end

    it 'rescues a \'TerribleMistake\' exception and performs a shutdown of chore' do
      allow(strategy).to receive(:worker_assignment_loop).and_raise(Chore::TerribleMistake)
      allow(manager).to receive(:shutdown!)
      allow(Thread).to receive(:new).and_yield
      expect(Process).to receive(:exit)
      strategy.send(:worker_assignment_thread)
    end
  end

  context '#worker_assignment_loop' do
    before(:each) do
      allow(socket).to receive(:send)

      allow(strategy).to receive(:running?).and_return(true, false)
      strategy.instance_variable_set(:@self_read, pipe)
      allow(strategy).to receive(:select_sockets).and_return([[socket], nil, nil])
      allow(strategy).to receive(:handle_self_pipe_signal).and_return(true)
      allow(strategy).to receive(:fetch_and_assign_jobs).and_return(true)

      allow(worker_manager).to receive(:worker_sockets).and_return([socket])
      allow(worker_manager).to receive(:ready_workers).and_yield([worker])
      allow(worker_manager).to receive(:destroy_expired!)

      allow(work_distributor).to receive(:fetch_and_assign_jobs)
    end

    it 'should terminate when @running is set to false' do
      allow(strategy).to receive(:running?).and_return(false)
      expect(strategy).to receive(:select_sockets).exactly(0).times
      strategy.send(:worker_assignment_loop)
    end

    it 'should get the worker_sockets' do
      expect(worker_manager).to receive(:worker_sockets)
      strategy.send(:worker_assignment_loop)
    end

    it 'should handle no sockets being ready' do
      allow(strategy).to receive(:select_sockets).and_return(nil)
      expect(strategy).to receive(:select_sockets).once
      strategy.send(:worker_assignment_loop)
    end

    it 'should handle signals if alerted on a self pipe' do
      allow(strategy).to receive(:select_sockets).and_return([[pipe], nil, nil])
      expect(strategy).to receive(:handle_signal).once
      strategy.send(:worker_assignment_loop)
    end

    it 'should check if sockets are writable' do
      allow(strategy).to receive(:handle_signal)
      expect(socket).to receive(:send).once
      strategy.send(:worker_assignment_loop)
    end

    it 'should not assign jobs if sockets are not writable' do
      allow(strategy).to receive(:handle_signal)
      allow(socket).to receive(:send).and_raise(IOError)
      expect(work_distributor).to_not receive(:fetch_and_assign_jobs)
      strategy.send(:worker_assignment_loop)
    end

    it 'should handle fetch and assign jobs when workers are ready' do
      expect(work_distributor).to receive(:fetch_and_assign_jobs).with([worker], manager).once
      strategy.send(:worker_assignment_loop)
    end
  end

  context '#handle_signal' do
    before(:each) do
      strategy.instance_variable_set(:@self_read, pipe)
      allow(pipe).to receive(:read_nonblock).and_return(nil)

      allow(worker_manager).to receive(:respawn_terminated_workers!).and_return(true)
      allow(worker_manager).to receive(:stop_workers).and_return(true)
      allow(manager).to receive(:shutdown!).and_return(true)
    end

    it 'should respawn terminated workers in the event of a SIGCHLD' do
      allow(pipe).to receive(:read_nonblock).and_return('1')
      expect(worker_manager).to receive(:respawn_terminated_workers!).once

      strategy.send(:handle_signal)
    end

    it 'should signal its children, and shutdown in the event of one of INT, QUIT or TERM signals' do
      allow(pipe).to receive(:read_nonblock).and_return('2', '3', '4')
      expect(worker_manager).to receive(:stop_workers).exactly(3).times
      expect(manager).to receive(:shutdown!).exactly(3).times
      3.times do
        strategy.send(:handle_signal)
      end
    end

    it 'should propagte the signal it receives to its children' do
      allow(pipe).to receive(:read_nonblock).and_return('3')
      expect(worker_manager).to receive(:stop_workers).with(:QUIT)
      strategy.send(:handle_signal)
    end

    it 'should reset logs on a USR1 signal' do
      allow(pipe).to receive(:read_nonblock).and_return('5')
      expect(Chore).to receive(:reopen_logs)
      strategy.send(:handle_signal)
    end

    it 'should not preform any task when an unhandled signal is called' do
      allow(pipe).to receive(:read_nonblock).and_return('9')
      expect(worker_manager).to receive(:respawn_terminated_workers!).exactly(0).times
      expect(worker_manager).to receive(:stop_workers).exactly(0).times
      expect(manager).to receive(:shutdown!).exactly(0).times
      strategy.send(:handle_signal)
    end
  end

  context '#trap_signals' do
    before(:each) do
      allow_any_instance_of(Chore::Strategy::PreForkedWorkerStrategy).to receive(:trap_signals).and_call_original
    end

    let(:signals) { { '1' => 'QUIT' } }

    it 'should reset signals' do
      allow(Chore::Signal).to receive(:reset)
      expect(Chore::Signal).to receive(:reset)
      strategy.send(:trap_signals, {}, pipe)
    end

    it 'should trap the signals passed to it' do
      allow(Chore::Signal).to receive(:reset)
      expect(Chore::Signal).to receive(:trap).with('QUIT').once
      strategy.send(:trap_signals, signals, pipe)
    end
  end
end
