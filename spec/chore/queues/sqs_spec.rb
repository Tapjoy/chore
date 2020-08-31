require 'spec_helper'

describe Chore::Queues::SQS do
  include_context 'fake objects'

  context "when managing queues" do
    before(:each) do
      allow(Aws::SQS::Client).to receive(:new).and_return(sqs)
      allow(sqs).to receive(:create_queue).and_return(queue)
      allow(sqs).to receive(:delete_queue).and_return(Struct.new(nil))
      allow(queue).to receive(:delete).and_return(sqs.delete_queue(queue))
      allow(Chore).to receive(:prefixed_queue_names).and_return([queue_name])
      allow(queue).to receive(:delete)
    end

    it 'should create queues that are defined in its internal job name list' do
      #Only one job defined in the spec suite
      expect(sqs).to receive(:create_queue).with(queue_name: queue_name)
      Chore::Queues::SQS.create_queues!
    end

    it 'should delete queues that are defined in its internal job name list' do
      #Only one job defined in the spec suite
      expect(sqs).to receive(:delete_queue).with(queue_url: sqs.get_queue_url.queue_url)
      Chore::Queues::SQS.delete_queues!
    end

    context 'and checking for existing queues' do
      it 'checks for existing queues' do
        expect(described_class).to receive(:existing_queues).and_return([])
        Chore::Queues::SQS.create_queues!(true)
      end

      it 'raises an error if a queue does exist' do
        allow(described_class).to receive(:existing_queues).and_return([queue_name])
        expect{Chore::Queues::SQS.create_queues!(true)}.to raise_error(RuntimeError)
      end

      it 'does not raise an error if a queue does not exist' do
        allow(described_class).to receive(:existing_queues).and_return([])
        expect{Chore::Queues::SQS.create_queues!(true)}.not_to raise_error
      end
    end
  end
end
