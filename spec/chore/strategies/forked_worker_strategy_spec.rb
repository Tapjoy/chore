require 'spec_helper'
require 'securerandom'

module Chore
  
  ## Rewrite the fork and thread methods so we can test sanely
  class ForkedWorkerStrategy
    def fork(&block)
      block.call
    end
    def thread(&block)
      block.call
    end
  end

  describe ForkedWorkerStrategy do
    let(:manager) { double('manager') }
    let(:forker) { ForkedWorkerStrategy.new(manager) }
    let(:job) { UnitOfWork.new(SecureRandom.uuid, JsonEncoder.encode(TestJob.job_hash([1,2,"3"]))) }
    let(:pid) { Random.rand(2048) }

    context '#assign' do
      before(:each) do
        forker.stub(:after_fork)
        Process.stub(:wait2)
      end

      it 'should not start working if there are no workers available' do
        forker.workers.should_receive(:length).and_return(Chore.config.num_workers)
        Worker.any_instance.should_not_receive(:start)
        forker.assign(job)
      end

      it 'should assign a job to a new worker' do
        Worker.any_instance.should_receive(:start).with(job)
        forker.assign(job)
      end

      it 'should add an assigned worker to the worker list' do
        forker.should_receive(:fork).and_return(pid)
        forker.workers.should_receive(:[]=).with(pid,kind_of(Worker))
        forker.assign(job)
      end

      it 'should fork a child for each new worker' do
        forker.should_receive(:fork).and_return(pid)
        forker.assign(job)
      end

      it 'should reset the procline' do
        forker.should_receive(:procline)
        forker.assign(job)
      end

      it 'should remove the worker from the list when it has completed' do
        forker.should_receive(:fork).and_return(pid)
        forker.workers.should_receive(:delete).with(pid)
        forker.assign(job)
      end
    end
  end
end
