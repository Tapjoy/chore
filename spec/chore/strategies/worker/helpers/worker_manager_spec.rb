require 'spec_helper'
require 'chore/signal'
require 'chore/strategies/worker/helpers/worker_manager'

describe Chore::Strategy::WorkerManager do
  let(:master_socket) { double('master_socket') }

  let(:worker_manager) { Chore::Strategy::WorkerManager.new(master_socket) }


  let(:worker_pid_1) { 1 }
  let(:socket_1) { double('socket_1') }

  let(:worker_pid_2) { 2 }
  let(:socket_2) { double('socket_2') }

  let(:worker_pid_3) { 3 }

  let(:pid_sock_hash) { { worker_pid_1 => socket_1,
                          worker_pid_2 => socket_2 } }
  let(:pid_sock_hash_2) { { worker_pid_1 => socket_1 } }

  let(:pid_sock_hash_3) { { worker_pid_1 => socket_1,
                          worker_pid_2 => socket_2,
                          worker_pid_3 => nil } }

  let(:config) { double("config") }
  let(:worker) { double("worker") }

  let(:worker_info_1) { double('worker_info_1') }
  let(:worker_info_2) { double('worker_info_2') }

  let(:pid_to_worker) { {
                          worker_pid_1 => worker_info_1,
                          worker_pid_2 => worker_info_2
                      } }
  let(:socket_to_worker) { {
                          socket_1 => worker_info_1,
                          socket_2 => worker_info_2
                      } }

  context '#include_ipc' do
    it 'should include the Ipc module' do
      expect(worker_manager.ipc_help).to eq(:available)
    end
  end

  context '#create_and_attach_workers' do
    before(:each) do
      allow(worker_manager).to receive(:create_workers).and_yield(2)
      allow(worker_manager).to receive(:attach_workers).and_return(true)
    end

    it 'should call to create replacement workers' do
      expect(worker_manager).to receive(:create_workers)
      worker_manager.create_and_attach_workers
    end

    it 'should create a map between new workers to new sockets' do
      expect(worker_manager).to receive(:attach_workers).with(2)
      worker_manager.create_and_attach_workers
    end
  end

  context '#respawn_terminated_workers!' do
    before(:each) do
      allow(worker_manager).to receive(:create_and_attach_workers).and_return(true)
      allow(worker_manager).to receive(:reap_workers).and_return(true)
    end

    it 'should reap all the terminated worker processes' do
      expect(worker_manager).to receive(:reap_workers)
      worker_manager.respawn_terminated_workers!
    end

    it 'should re-create and attach all the workers that died' do
      expect(worker_manager).to receive(:create_and_attach_workers)
      worker_manager.respawn_terminated_workers!
    end
  end

  context '#stop_workers' do
    let(:signal) { 'TERM' }
    before(:each) do
      allow(Process).to receive(:kill).and_return(nil)
      allow(worker_manager).to receive(:reap_workers)
      worker_manager.instance_variable_set(:@pid_to_worker, pid_sock_hash)
    end

    it 'should forward the signal received to each of the child processes' do
      pid_sock_hash.each do |pid, sock|
        expect(Process).to receive(:kill).with(signal, pid)
      end
      worker_manager.stop_workers(signal)
    end

    it 'should reap all terminated child processes' do
      expect(worker_manager).to receive(:reap_workers)
      worker_manager.stop_workers(signal)
    end
  end

  context 'worker_sockets' do
    it 'should return a list of socket assoicated with workers' do
      worker_manager.instance_variable_set(:@socket_to_worker, socket_to_worker)
      res = worker_manager.worker_sockets
      expect(res).to eq([socket_1, socket_2])
    end
  end

  context '#ready_workers' do
    it 'should return a list of workers assoicated with given sockets' do
      worker_manager.instance_variable_set(:@socket_to_worker, socket_to_worker)
      allow(worker_info_1).to receive(:reset_start_time!)
      res = worker_manager.ready_workers([socket_1])
      expect(res).to eq([worker_info_1])
    end

    it 'should yield when a block is passed to it' do
      worker_manager.instance_variable_set(:@socket_to_worker, socket_to_worker)
      allow(worker_info_1).to receive(:reset_start_time!)
      expect{ |b| worker_manager.ready_workers([socket_1], &b) }.to yield_control
    end
  end

  context '#create_workers' do
    before(:each) do
      allow(worker_manager).to receive(:fork).and_yield
      allow(worker_manager).to receive(:run_worker_instance)
      allow(Chore).to receive(:config).and_return(config)
    end

    it 'should fork it running process till we have the right optimized number of workers and return the number of workers it created' do
      allow(config).to receive(:num_workers).and_return(1)
      expect(worker_manager).to receive(:fork).once
      expect(worker_manager).to receive(:run_worker_instance).once
      worker_manager.send(:create_workers)
    end

    it 'should raise an exception if an inconsistent number of workers are created' do
      allow(config).to receive(:num_workers).and_return(0)
      allow(worker_manager).to receive(:inconsistent_worker_number).and_return(true)
      expect(worker_manager).to receive(:inconsistent_worker_number)
      expect { worker_manager.send(:create_workers) }.to raise_error(RuntimeError)
    end

    it 'should call the block passed to it with the number of workers it created' do
      allow(config).to receive(:num_workers).and_return(0)
      allow(worker_manager).to receive(:inconsistent_worker_number).and_return(false)
      expect { |b| worker_manager.send(:create_workers, &b) }.to yield_control.once
    end
  end

  context '#inconsistent_worker_number' do
    it 'should check if the worker numbers match the number configured' do
      allow(Chore).to receive(:config).and_return(config)
      allow(config).to receive(:num_workers).and_return(2)
      worker_manager.instance_variable_set(:@pid_to_worker, pid_to_worker)
      res_false = worker_manager.send(:inconsistent_worker_number)
      allow(config).to receive(:num_workers).and_return(4)
      res_true = worker_manager.send(:inconsistent_worker_number)
      expect(res_true).to be(true)
      expect(res_false).to be(false)
    end
  end

  context '#run_worker_instance' do
    before(:each) do
      allow(Chore::Strategy::PreforkedWorker).to receive(:new).and_return(worker)
      allow(worker).to receive(:start_worker).and_return(true)
      allow(worker_manager).to receive(:exit!).and_return(true)
    end

    it 'should create a PreforkedWorker object and start it' do
      expect(Chore::Strategy::PreforkedWorker).to receive(:new).and_return(worker)
      expect(worker).to receive(:start_worker)
      worker_manager.send(:run_worker_instance)
    end

    it 'should ensure that the process exits when the PreforkedWorker completes' do
      expect(worker_manager).to receive(:exit!).with(true)
      worker_manager.send(:run_worker_instance)
    end
  end

  context '#attach_workers' do
    before(:each) do
      allow(worker_manager).to receive(:create_worker_sockets).and_return([socket_1, socket_2])
      allow(worker_manager).to receive(:read_from_worker).and_return(worker_pid_1, worker_pid_2)
      allow(worker_manager).to receive(:kill_unattached_workers).and_return(true)
      worker_manager.instance_variable_set(:@pid_to_worker, pid_to_worker)
      worker_manager.instance_variable_set(:@socket_to_worker, {})
      allow(worker_info_1).to receive(:socket=)
      allow(worker_info_2).to receive(:socket=)
    end

    it 'should add as many sockets as the number passed to it as a param' do
      expect(worker_manager).to receive(:read_from_worker).twice
      worker_manager.send(:attach_workers, 2)
    end

    it 'should get the PID from each socket it creates and map that to the worker that it is connected to' do
      worker_manager.send(:attach_workers, 2)
      expect(worker_manager.instance_variable_get(:@socket_to_worker)).to eq(socket_to_worker)
    end

    it 'should kill any unattached workers' do
      expect(worker_manager).to receive(:kill_unattached_workers)
      worker_manager.send(:attach_workers, 2)
    end
  end

  context "#create_worker_sockets" do
    it 'should return an array of sockets equal to the number passed to it' do
      allow(worker_manager).to receive(:add_worker_socket).and_return(socket_1, socket_2, socket_2, socket_1)
      num = 3
      res = worker_manager.send(:create_worker_sockets, num)
      expect(res.size).to eq(num)
    end
  end

  context "#kill_unattached_workers" do
    it 'should send a kill -9 to PIDs that do not have a socket attached to them' do
      worker_manager.instance_variable_set(:@pid_to_worker, pid_to_worker)
      allow(worker_info_1).to receive(:socket).and_return(socket_1)
      allow(worker_info_2).to receive(:socket).and_return(nil)
      allow(Process).to receive(:kill).and_return(true)
      expect(Process).to receive(:kill).with('KILL', worker_pid_2).once
      worker_manager.send(:kill_unattached_workers)
    end
  end

  context "#reap_workers" do
    before(:each) do
      worker_manager.instance_variable_set(:@pid_to_worker, pid_to_worker)
      allow(worker_info_1).to receive(:socket).and_return(socket_1)
      allow(worker_info_1).to receive(:pid).and_return(worker_pid_1)
      allow(worker_info_2).to receive(:socket).and_return(socket_2)
      allow(worker_info_2).to receive(:pid).and_return(worker_pid_2)
    end

    it 'should run through each worker-pid map and delete the worker pids from the hash, if they were dead' do
      allow(worker_manager).to receive(:reap_process).and_return(false, true)
      expect(worker_manager.instance_variable_get(:@pid_to_worker).size).to eq(2)
      worker_manager.send(:reap_workers)
      expect(worker_manager.instance_variable_get(:@pid_to_worker).size).to eq(1)
    end

    it 'should not change the worker pids map, if all the childern are running' do
      allow(worker_manager).to receive(:reap_process).and_return(false, false)
      expect(worker_manager.instance_variable_get(:@pid_to_worker).size).to eq(2)
      worker_manager.send(:reap_workers)
      expect(worker_manager.instance_variable_get(:@pid_to_worker).size).to eq(2)
    end
  end

  context "#reap_worker" do
    it 'should return true if the pid was dead' do
      allow(Process).to receive(:wait).and_return(worker_pid_1)
      res = worker_manager.send(:reap_process, worker_pid_1)
      expect(res).to eq(true)
    end

    it 'should return false if the pid was running' do
      allow(Process).to receive(:wait).and_return(nil)
      res = worker_manager.send(:reap_process, worker_pid_1)
      expect(res).to eq(false)
    end

    it 'should return true if the pid was dead' do
     allow(Process).to receive(:wait).and_raise(Errno::ECHILD)
     res = worker_manager.send(:reap_process, worker_pid_1)
     expect(res).to eq(true)
   end   
 end
end
