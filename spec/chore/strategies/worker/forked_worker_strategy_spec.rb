require 'spec_helper'
require 'securerandom'

module Chore
  module Strategy
    describe ForkedWorkerStrategy do
      let(:manager) { double('manager') }
      let(:forker) { ForkedWorkerStrategy.new(manager) }
      let(:job) { UnitOfWork.new(SecureRandom.uuid, JsonEncoder.encode(TestJob.job_hash([1,2,"3"])), 0) }
      let(:worker) { Worker.new(job) }
      let(:pid) { Random.rand(2048) }

      context "signal handling" do
        it 'should trap signals from terminating children and reap them' do
          ForkedWorkerStrategy.any_instance.should_receive(:trap).with('CHLD').and_yield
          ForkedWorkerStrategy.any_instance.should_receive(:reap_terminated_workers!)
          forker
        end
      end

      context '#assign' do
        before(:each) do
          forker.stub(:fork).and_yield.and_return(pid)
          forker.stub(:after_fork)
          worker #can't let this resolve lazily
        end
        after(:each) do
          Chore.clear_hooks!
        end

        it 'should not start working if there are no workers available' do
          forker.workers.should_receive(:length).and_return(Chore.config.num_workers)
          Worker.any_instance.should_not_receive(:start)
          forker.assign(job)
        end

        it 'should assign a job to a new worker' do
          Worker.should_receive(:new).with(job).and_return(worker)
          worker.should_receive(:start)
          forker.assign(job)
        end

        it 'should add an assigned worker to the worker list' do
          forker.workers.should_receive(:[]=).with(pid,kind_of(Worker))
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

        [:before_fork, :after_fork, :before_fork_shutdown].each do |hook|
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
          Worker.stub(:new).and_return(worker)
          worker.stub(:start).and_raise(ArgumentError)

          hook_called = false
          Chore.add_hook(:before_fork_shutdown) { hook_called = true }
          
          begin
            forker.assign(job)
          rescue ArgumentError => ex
          end

          hook_called.should be_true
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
    end
  end
end
