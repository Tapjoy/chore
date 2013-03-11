require 'spec_helper'
require 'securerandom'

module Chore

  describe ForkedWorkerStrategy do
    let(:manager) { double('manager') }
    let(:forker) { ForkedWorkerStrategy.new(manager) }
    let(:job) { UnitOfWork.new(SecureRandom.uuid, JsonEncoder.encode(TestJob.job_hash([1,2,"3"]))) }
    let(:worker) { Worker.new(job) }
    let(:pid) { Random.rand(2048) }

    context "signal handling" do
      it 'should trap signals from terminating children and reap them' do
        ForkedWorkerStrategy.any_instance.should_receive(:trap).with('CHLD').and_yield
        ForkedWorkerStrategy.any_instance.should_receive(:reap_terminated_workers)
        forker
      end
    end

    context '#assign' do
      before(:each) do
        forker.stub(:fork).and_yield.and_return(pid)
        forker.stub(:after_fork)
        worker #can't let this resolve lazily
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
        forker.reap_terminated_workers

        forker.workers.should_not include(pid)
      end
    end
  end

  describe StatListener do
    let(:listener) { StatListener.new(1) }
    let(:entry) { StatEntry.new(:test,nil) }
    let(:event) { :completed }
    let(:payload) { Marshal.dump([event,entry]) }

    it 'should add to the stats when given a valid payload' do
      Chore.stats.should_receive(:add).with(event,kind_of(StatEntry))
      listener.handle_payload(payload)
    end
  end
end
