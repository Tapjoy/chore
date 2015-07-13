require 'spec_helper'

describe Chore::Strategy::SingleWorkerStrategy do
  let(:manager) { double('Manager') }
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

end
