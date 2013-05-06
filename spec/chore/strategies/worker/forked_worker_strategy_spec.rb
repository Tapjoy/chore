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

    end

    context '#after_fork' do
      let(:worker) { double('worker') }
      before(:all) { @stats = Chore.stats }

      it 'should clear signals' do
        forker.should_receive(:clear_child_signals)
        forker.should_receive(:trap_child_signals)
        forker.send(:after_fork,worker)
      end

      it 'should reset Chore.stats' do
        forker.send(:after_fork,worker)
        Chore.stats.should be_kind_of(PipedStats)
      end

      it "should replace the worker's status= method" do
        worker.methods.find {|m| m.to_s == 'status='}.should be_nil
        forker.send(:after_fork,worker)
        worker.methods.find {|m| m.to_s == 'status='}.should_not be_nil
      end

      after(:all) { Chore.stats = @stats }
    end
  end

  describe WorkerListener do
    let(:parent) { double('parent').as_null_object }
    let(:worker) { double('worker').as_null_object }
    let(:listener) { WorkerListener.new(parent,1) }

    context 'stat payloads' do
      let(:entry) { StatEntry.new(:test,nil) }
      let(:event) { :completed }
      let(:payload) { Marshal.dump({'type'=>'stat','value'=>[event,entry]}) }

      it 'should add to the stats when given a valid payload' do
        Chore.stats.should_receive(:add).with(event,kind_of(StatEntry))
        listener.handle_payload(payload)
      end
    end

    context 'status payloads' do
      let(:id) { Random.rand(2048) }
      let(:status) { 'some-status'}
      let(:payload) { Marshal.dump({'type'=>'status','value'=>{'id'=>id,'status'=>status }})}
      it 'should attempt to set the status on the parent when receiving a status object' do
        worker.should_receive(:status=).with(status)
        parent.workers.should_receive(:[]).with(id).and_return(worker)
        listener.handle_payload(payload)
      end
    end
  end
end
