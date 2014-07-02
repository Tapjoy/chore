require 'spec_helper'

describe Chore::Strategy::SingleWorkerStrategy do
  let(:manager) { mock('Manager') }
  subject       { described_class.new(manager) }

  describe '#stop!' do
    before(:each) do
      subject.stub(:worker).and_return worker
    end

    context 'given there is no current worker' do
      let(:worker)  { nil }

      it 'does nothing' do
        allow_message_expectations_on_nil
        
        worker.should_not_receive(:stop!)
        subject.stop!
      end
    end

    context 'given there is a current worker' do
      let(:worker)  { mock('Worker') }
      before(:each) do
        subject.stub(:worker).and_return worker
      end

      it 'stops the worker' do
        worker.should_receive(:stop!)
        subject.stop!
      end
    end
  end

end
