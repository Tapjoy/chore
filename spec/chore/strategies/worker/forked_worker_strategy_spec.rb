require 'spec_helper'
require 'securerandom'

describe Chore::Strategy::ForkedWorkerStrategy do
  let(:manager) { double('manager') }
  let(:forker) do
    strategy = Chore::Strategy::ForkedWorkerStrategy.new(manager)
    allow(strategy).to receive(:exit!)
    strategy
  end
  let(:consumer) { double('consumer', :complete => nil, :reject => nil) }
  let(:job_timeout) { 60 }
  let(:job) do
    Chore::UnitOfWork.new(
      SecureRandom.uuid,
      'test',
      job_timeout,
      Chore::Encoder::JsonEncoder.encode(TestJob.job_hash([1,2,"3"])),
      0,
      consumer
    )
  end
  let!(:worker) { Chore::Worker.new(job) }
  let(:pid) { Random.rand(2048) }

  after(:each) do
    allow(Process).to receive(:kill) { nil }
    allow(Process).to receive(:wait) { pid }
    forker.stop!
  end

  context "signal handling" do
    it 'should trap signals from terminating children and reap them' do
      expect(Chore::Signal).to receive(:trap).with('CHLD').and_yield
      allow_any_instance_of(Chore::Strategy::ForkedWorkerStrategy).to receive(:reap_terminated_workers!)
      forker
    end
  end

  context '#assign' do
    before(:each) do
      allow(forker).to receive(:fork).and_yield.and_return(pid, pid + 1)
      allow(forker).to receive(:after_fork)
    end
    after(:each) do
      Chore.clear_hooks!
    end

    it 'should pop off the worker queue when assignd a job' do
      allow_any_instance_of(Queue).to receive(:pop)
      forker.assign(job)
    end

    it 'should assign a job to a new worker' do
      expect(Chore::Worker).to receive(:new).with(job, {}).and_return(worker)
      expect(worker).to receive(:start)
      forker.assign(job)
    end

    it 'should add an assigned worker to the worker list' do
      expect(forker.workers).to receive(:[]=).with(pid,kind_of(Chore::Worker))
      forker.assign(job)
    end

    it 'should fork a child for each new worker' do
      expect(forker).to receive(:fork).and_yield.and_return(pid)
      forker.assign(job)
    end

    it 'should remove the worker from the list when it has completed' do
      forker.assign(job)

      expect(Process).to receive(:wait).with(pid, Process::WNOHANG).and_return(pid)
      forker.send(:reap_terminated_workers!)

      expect(forker.workers).to_not include(pid)
    end

    it 'should not remove the worker from the list if it has not yet completed' do
      forker.assign(job)

      expect(Process).to receive(:wait).and_return(nil)
      forker.send(:reap_terminated_workers!)

      expect(forker.workers).to include(pid)
    end

    it 'should add the worker back to the queue when it has completed' do
      2.times { forker.assign(job) }

      allow_any_instance_of(Queue).to receive(:<<).with(:worker)

      allow(Process).to receive(:wait).and_return(pid, pid + 1)
      forker.send(:reap_terminated_workers!)
    end

    it 'should only release a worker once if reaped twice' do
      forker.assign(job)
      reaped = false

      expect(forker).to receive(:release_worker).once

      wait_proc = Proc.new do
        if !reaped
          reaped = true
          forker.send(:reap_terminated_workers!)
        end

        pid
      end

      expect(Process).to receive(:wait).with(pid, anything).and_return(wait_proc)
      forker.send(:reap_terminated_workers!)
    end

    it 'should continue to allow reaping after an exception occurs' do
      2.times { forker.assign(job) }

      expect(Process).to receive(:wait).and_raise(Errno::ECHILD)
      expect(Process).to receive(:wait).and_return(pid + 1)
      forker.send(:reap_terminated_workers!)

      expect(forker.workers).to eq({})
    end

    [:before_fork, :after_fork, :within_fork, :before_fork_shutdown].each do |hook|
      it "should run #{hook} hooks" do
        hook_called = false
        Chore.add_hook(hook) { hook_called = true }
        forker.assign(job)
        expect(hook_called).to be true
      end
    end

    it 'should run around_fork hooks' do
      hook_called = false
      Chore.add_hook(:around_fork) {|&blk| hook_called = true; blk.call }
      forker.assign(job)
      expect(hook_called).to be true
    end

    it 'should run before_fork_shutdown hooks even if job errors' do
      expect(Chore::Worker).to receive(:new).and_return(worker)
      expect(worker).to receive(:start).and_raise(ArgumentError)

      hook_called = false
      Chore.add_hook(:before_fork_shutdown) { hook_called = true }

      begin
        forker.assign(job)
      rescue ArgumentError
      end

      expect(hook_called).to be true
    end

    it 'should exit the process without running at_exit handlers' do
      expect(forker).to receive(:exit!).with(true)
      forker.assign(job)
    end

    context 'long-lived work' do
      let(:job_timeout) { 0.1 }

      before(:each) do
        allow(Process).to receive(:kill)
        expect(Chore::Worker).to receive(:new).and_return(worker)
      end

      it 'should kill the process if it expires' do
        expect(Process).to receive(:kill).with('KILL', pid)
        forker.assign(job)
        sleep 2
      end

      it 'should run the on_failure callback hook' do
        forker.assign(job)
        expect(Chore).to receive(:run_hooks_for).with(:on_failure, anything, instance_of(Chore::TimeoutError))
        sleep 2
      end
    end

    context 'short-lived work' do
      let(:job_timeout) { 0.1 }

      before(:each) do
        expect(Chore::Worker).to receive(:new).and_return(worker)
      end

      it 'should not kill the process if does not expire' do
        expect(Process).to_not receive(:kill)

        forker.assign(job)
        expect(Process).to receive(:wait).and_return(pid)
        forker.send(:reap_terminated_workers!)
        sleep 2
      end
    end
  end

  context '#before_fork' do
    before(:each) do
      expect(Chore::Worker).to receive(:new).and_return(worker)
    end
    after(:each) do
      Chore.clear_hooks!
    end

    it 'should release the worker if an exception occurs' do
      Chore.add_hook(:before_fork) { raise ArgumentError }
      expect(forker).to receive(:release_worker)
      forker.assign(job)
    end
  end

  context '#around_fork' do
    before(:each) do
      expect(Chore::Worker).to receive(:new).and_return(worker)
    end
    after(:each) do
      Chore.clear_hooks!
    end

    it 'should release the worker if an exception occurs' do
      Chore.add_hook(:around_fork) {|worker, &block| raise ArgumentError}
      expect(forker).to receive(:release_worker)
      forker.assign(job)
    end
  end

  context '#after_fork' do
    let(:worker) { double('worker') }

    it 'should clear signals' do
      expect(forker).to receive(:clear_child_signals)
      forker.send(:after_fork,worker)
    end

    it 'should trap signals' do
      expect(forker).to receive(:trap_child_signals)
      forker.send(:after_fork,worker)
    end

    it 'should set the procline' do
      expect(forker).to receive(:procline)
      forker.send(:after_fork,worker)
    end
  end

  context '#stop!' do
    before(:each) do
      allow(Process).to receive(:kill)

      expect(forker).to receive(:fork).and_yield.and_return(pid)
      expect(forker).to receive(:after_fork)
      forker.assign(job)
    end

    it 'should send a quit signal to each child' do
      expect(Process).to receive(:kill).once.with('QUIT', pid)
      allow(Process).to receive(:wait).and_return(pid, nil)
      forker.stop!
    end

    it 'should reap each worker' do
      expect(Process).to receive(:wait).and_return(pid)
      forker.stop!
      expect(forker.workers).to eq({})
    end

    it 'should resend quit signal to children if workers are not reaped' do
      expect(Process).to receive(:kill).with('QUIT', pid)
      allow(Process).to receive(:wait).and_return(nil, pid, nil)
      forker.stop!
    end

    it 'should send kill signal to children if timeout is exceeded' do
      expect(Chore.config).to receive(:shutdown_timeout).and_return(0.05)
      expect(Process).to receive(:kill).once.with('QUIT', pid)
      expect(Process).to receive(:wait).and_return(nil)
      expect(Process).to receive(:kill).once.with('KILL', pid)
      forker.stop!
    end

    it 'should not allow more work to be assigned' do
      allow(Process).to receive(:wait).and_return(pid, nil)
      forker.stop!

      expect(Chore::Worker).to_not receive(:new)
      forker.assign(job)
    end
  end
end

