require 'spec_helper'
require 'securerandom'

describe Chore::Strategy::ForkedWorkerStrategy do
  let(:manager) { double('manager') }
  let(:forker) do
    strategy = Chore::Strategy::ForkedWorkerStrategy.new(manager)
    strategy.stub(:exit!)
    strategy
  end
  let(:job) { Chore::UnitOfWork.new(SecureRandom.uuid, 'test', Chore::JsonEncoder.encode(TestJob.job_hash([1,2,"3"])), 0) }
  let!(:worker) { Chore::Worker.new(job) }
  let(:pid) { Random.rand(2048) }

  context "signal handling" do
    it 'should trap signals from terminating children and reap them' do
      Chore::Strategy::ForkedWorkerStrategy.any_instance.should_receive(:trap).with('CHLD').and_yield
      Chore::Strategy::ForkedWorkerStrategy.any_instance.should_receive(:reap_terminated_workers!)
      forker
    end
  end

  context '#assign' do
    before(:each) do
      forker.stub(:fork).and_yield.and_return(pid)
      forker.stub(:after_fork)
    end
    after(:each) do
      Chore.clear_hooks!
    end

    it 'should pop off the worker queue when assignd a job' do
      Queue.any_instance.should_receive(:pop)
      forker.assign(job)
    end

    it 'should assign a job to a new worker' do
      Chore::Worker.should_receive(:new).with(job).and_return(worker)
      worker.should_receive(:start)
      forker.assign(job)
    end

    it 'should add an assigned worker to the worker list' do
      forker.workers.should_receive(:[]=).with(pid,kind_of(Chore::Worker))
      forker.assign(job)
    end

    it 'should fork a child for each new worker' do
      forker.should_receive(:fork).and_yield.and_return(pid)
      forker.assign(job)
    end

    it 'should reset the procline' do
      forker.should_receive(:procline)
      forker.assign(job)
    end

    it 'should remove the worker from the list when it has completed' do
      forker.assign(job)

      Process.should_receive(:wait).and_return(pid, nil)
      forker.send(:reap_terminated_workers!)

      forker.workers.should_not include(pid)
    end

    it 'should add the worker back to the queue when it has completed' do
      forker.assign(job)

      Queue.any_instance.should_receive(:<<).twice.with(:worker)

      Process.stub(:wait).and_return(pid, pid + 1, nil)
      forker.send(:reap_terminated_workers!)
    end

    it 'should not allow more than one thread to reap terminated workers' do
      forker.assign(job)

      Process.should_receive(:wait).and_return do
        Process.should_not_receive(:wait)
        forker.send(:reap_terminated_workers!)

        nil
      end
      forker.send(:reap_terminated_workers!)
    end

    it 'should continue to allow reaping after an exception occurs' do
      forker.assign(job)

      Process.stub(:wait).and_raise(Errno::ECHILD)
      forker.send(:reap_terminated_workers!)

      Process.should_receive(:wait).and_return(pid, nil)
      forker.send(:reap_terminated_workers!)
    end

    [:before_fork, :after_fork, :within_fork, :before_fork_shutdown].each do |hook|
      it "should run #{hook} hooks" do
        hook_called = false
        Chore.add_hook(hook) { hook_called = true }
        forker.assign(job)
        hook_called.should be_true
      end
    end

    it 'should run around_fork hooks' do
      hook_called = false
      Chore.add_hook(:around_fork) {|&blk| hook_called = true; blk.call }
      forker.assign(job)
      hook_called.should be_true
    end

    it 'should run before_fork_shutdown hooks even if job errors' do
      Chore::Worker.stub(:new).and_return(worker)
      worker.stub(:start).and_raise(ArgumentError)

      hook_called = false
      Chore.add_hook(:before_fork_shutdown) { hook_called = true }

      begin
        forker.assign(job)
      rescue ArgumentError => ex
      end

      hook_called.should be_true
    end

    it 'should exit the process without running at_exit handlers' do
      forker.should_receive(:exit!).with(true)
      forker.assign(job)
    end
  end

  context '#before_fork' do
    before(:each) do
      Chore::Worker.stub(:new).and_return(worker)
    end
    after(:each) do
      Chore.clear_hooks!
    end

    it 'should release the worker if an exception occurs' do
      Chore.add_hook(:before_fork) { raise ArgumentError }
      forker.should_receive(:release_worker)
      forker.assign(job)
    end
  end

  context '#around_fork' do
    before(:each) do
      Chore::Worker.stub(:new).and_return(worker)
    end
    after(:each) do
      Chore.clear_hooks!
    end

    it 'should release the worker if an exception occurs' do
      Chore.add_hook(:around_fork) {|worker, &block| raise ArgumentError}
      forker.should_receive(:release_worker)
      forker.assign(job)
    end
  end

  context '#after_fork' do
    let(:worker) { double('worker') }

    it 'should clear signals' do
      forker.should_receive(:clear_child_signals)
      forker.should_receive(:trap_child_signals)
      forker.send(:after_fork,worker)
    end
  end

  context '#stop!' do
    before(:each) do
      Process.stub(:kill)

      forker.stub(:fork).and_yield.and_return(pid)
      forker.stub(:after_fork)
      forker.assign(job)
    end

    it 'should send a quit signal to each child' do
      Process.should_receive(:kill).once.with('QUIT', pid)
      Process.stub(:wait).and_return(pid, nil)
      forker.stop!
    end

    it 'should reap each worker' do
      Process.should_receive(:wait).and_return(pid, nil)
      forker.stop!
      forker.workers.should be_empty
    end

    it 'should resend quit signal to children if workers are not reaped' do
      Process.should_receive(:kill).twice.with('QUIT', pid)
      Process.stub(:wait).and_return(nil, pid, nil)
      forker.stop!
    end

    it 'should send kill signal to children if timeout is exceeded' do
      Chore.config.stub(:shutdown_timeout).and_return(0.05)
      Process.should_receive(:kill).once.with('QUIT', pid)
      Process.stub(:wait).and_return(nil)
      Process.should_receive(:kill).once.with('KILL', pid)
      forker.stop!
    end
  end
end

