require 'spec_helper'

describe Chore::Strategy::SingleWorkerStrategy do
  let(:manager) { double('Manager') }
  let(:job_timeout) { 60 }
  let(:job) { Chore::UnitOfWork.new(SecureRandom.uuid, nil, 'test', job_timeout, Chore::Encoder::JsonEncoder.encode(TestJob.job_hash([1,2,"3"])), 0) }
  subject       { described_class.new(manager) }

  describe '#stop!' do
    before(:each) do
      expect(subject).to receive(:worker).and_return worker
    end

    context 'given there is no current worker' do
      let(:worker)  { nil }

      it 'does nothing' do
        expect(worker).to_not receive(:stop!)
        subject.stop!
      end
    end

    context 'given there is a current worker' do
      let(:worker)  { double('Worker') }
      before(:each) do
        expect(subject).to receive(:worker).and_return worker
      end

      it 'stops the worker' do
        expect(worker).to receive(:stop!)
        subject.stop!
      end
    end
  end

  describe '#assign' do
    let(:worker) { double('Worker', start: nil) }

    it 'starts a new worker' do
      expect(Chore::Worker).to receive(:new).with(job, {}).and_return(worker)
      subject.assign(job)
    end

    it 'can be called multiple times' do
      expect(Chore::Worker).to receive(:new).twice.with(job, {}).and_return(worker)
      2.times { subject.assign(job) }
    end

    it 'should release the worker if an exception occurs' do
      allow_any_instance_of(Chore::Worker).to receive(:start).and_raise(ArgumentError)
      expect(subject).to receive(:release_worker)

      begin
        subject.assign(job)
      rescue ArgumentError
      end
    end
  end
end
