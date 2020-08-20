require 'spec_helper'
require 'chore/strategies/worker/helpers/work_distributor'

describe Chore::Strategy::WorkDistributor do
  let(:timestamp) { Time.now }
  let(:manager) { double('manager') }
  let(:worker) { Chore::Strategy::WorkerInfo.new(1) }
  let(:consumer) { double('consumer') }
  let(:job) do
    Chore::UnitOfWork.new(
      SecureRandom.uuid,
      'test',
      60,
      Chore::Encoder::JsonEncoder.encode(TestJob.job_hash([1,2,"3"])),
      0
    )
  end
  let(:socket) { double('socket') }

  context '#include_ipc' do
    it 'should include the Ipc module' do
      expect(described_class.ipc_help).to eq(:available)
    end
  end

  context '#fetch_and_assign_jobs' do
    it 'should fetch jobs from the consumer' do
      allow(described_class).to receive(:assign_jobs).and_return(true)
      allow(manager).to receive(:fetch_work).with(1).and_return([job])
      allow(manager).to receive(:return_work)
      expect(manager).to receive(:fetch_work).with(1)
      described_class.fetch_and_assign_jobs([worker], manager)
    end

    it 'should assign the fetched jobs to the workers' do
      allow(manager).to receive(:fetch_work).with(1).and_return([job])
      allow(manager).to receive(:return_work)
      expect(described_class).to receive(:assign_jobs).with([job], [worker])
      described_class.fetch_and_assign_jobs([worker], manager)
    end

    it 'should not return any work' do
      allow(described_class).to receive(:assign_jobs).and_return([])
      allow(manager).to receive(:fetch_work).with(1).and_return([job])
      expect(manager).to receive(:return_work).with([])
      described_class.fetch_and_assign_jobs([worker], manager)
    end

    it 'should raise and exception if it does not get an array from the manager' do
      allow(manager).to receive(:fetch_work).with(1).and_return(nil)
      allow(manager).to receive(:return_work)
      expect { described_class.fetch_and_assign_jobs([worker], manager) }.to raise_error("DW: jobs needs to be a list got NilClass")
    end

    it 'should sleep if no jobs are available' do
      expect(described_class).to receive(:sleep).with(0.1)
      allow(manager).to receive(:fetch_work).with(1).and_return([])
      allow(manager).to receive(:return_work)
      described_class.fetch_and_assign_jobs([worker], manager)
    end
  end

  context '#assign_jobs' do
    it 'should raise an exception if we have no free workers' do
      expect { described_class.send(:assign_jobs, [job], []) }.to raise_error('DW: assign_jobs got 0 workers')
    end

    it 'should remove the consumer object from the job object' do
      allow(described_class).to receive(:push_job_to_worker).and_return(true)

      described_class.send(:assign_jobs, [job], [worker])
    end

    it 'should raise an exception if more jobs than workers are provided to it' do
      allow(described_class).to receive(:push_job_to_worker).and_return(true)

      expect { described_class.send(:assign_jobs, [job, job], [worker]) }.to raise_error('DW: More Jobs than Sockets')
    end

    it 'should send the job object to the free worker' do
      allow(described_class).to receive(:push_job_to_worker).and_return(true)

      expect(described_class).to receive(:push_job_to_worker).with(job, worker)
      described_class.send(:assign_jobs, [job], [worker])
    end

    it 'should return jobs that failed to be assigned' do
      job2 = Chore::UnitOfWork.new(
        SecureRandom.uuid,
        'test',
        60,
        Chore::Encoder::JsonEncoder.encode(TestJob.job_hash([1,2,"3"])),
        0
      )
      worker2 = Chore::Strategy::WorkerInfo.new(2)

      allow(described_class).to receive(:push_job_to_worker).and_return(true, false)

      expect(described_class).to receive(:push_job_to_worker).with(job, worker)
      expect(described_class).to receive(:push_job_to_worker).with(job2, worker2)
      unassigned_jobs = described_class.send(:assign_jobs, [job, job2], [worker, worker2])
      expect(unassigned_jobs).to eq([job2])
    end
  end

  context '#push_job_to_worker' do
    before(:each) do
      allow(described_class).to receive(:clear_ready).with(worker.socket).and_return(true)
      allow(described_class).to receive(:send_msg).with(worker.socket, job).and_return(true)
    end

    it 'should clear all signals from the worker' do
      expect(described_class).to receive(:clear_ready).with(worker.socket)
      described_class.send(:push_job_to_worker, job, worker)
    end

    it 'should send the job as a message on the worker' do
      expect(described_class).to receive(:send_msg).with(worker.socket, job)
      described_class.send(:push_job_to_worker, job, worker)
    end

    it 'should return true if job successfully sent' do
      expect(described_class.send(:push_job_to_worker, job, worker)).to eq(true)
    end

    it 'should return false if job failed to send' do
      expect(described_class).to receive(:send_msg).and_raise(StandardError)
      expect(described_class.send(:push_job_to_worker, job, worker)).to eq(false)
    end
  end
end
