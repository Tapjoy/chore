require 'spec_helper'

module Chore
  describe Queues::SQS do
    context "when managing queues" do
      let(:fake_sqs) {double(Object)}
      let(:fake_queue_collection) {double(Object)}
      let(:queue_name) {"test"}
      let(:queue_url) {"http://amazon.sqs.url/queues/#{queue_name}"}
      let(:fake_queue) {double(Object)}

      before(:each) do
        allow(AWS::SQS).to receive(:new).and_return(fake_sqs)
        allow(Chore).to receive(:prefixed_queue_names).and_return([queue_name])
        allow(fake_queue).to receive(:delete)

        allow(fake_queue_collection).to receive(:[]).and_return(fake_queue)
        allow(fake_queue_collection).to receive(:create)
        allow(fake_queue_collection).to receive(:url_for).with(queue_name).and_return(queue_url)

        allow(fake_sqs).to receive(:queues).and_return(fake_queue_collection)
      end

      it 'should create queues that are defined in its internal job name list' do
        #Only one job defined in the spec suite
        expect(fake_queue_collection).to receive(:create)
        Chore::Queues::SQS.create_queues!
      end

      it 'should delete queues that are defined in its internal job name list' do
        #Only one job defined in the spec suite
        expect(fake_queue).to receive(:delete)
        Chore::Queues::SQS.delete_queues!
      end
    end
  end
end
