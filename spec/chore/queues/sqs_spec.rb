module Chore
  describe Queues::SQS do
    context "when managing queues" do
      let(:fake_sqs) {double(Object)}
      let(:fake_queue_collection) {double(Object)}
      let(:queue_name) {"test"}
      let(:queue_url) {"http://amazon.sqs.url/queues/#{queue_name}"}
      let(:fake_queue) {double(Object)}

      before(:each) do
        AWS::SQS.stub(:new).and_return(fake_sqs)
        Chore.stub(:prefixed_queue_names) {[queue_name]}
        fake_queue.stub(:delete)
    
        fake_queue_collection.stub(:[]) do |key|
          fake_queue
        end
    
        fake_queue_collection.stub(:create)
        fake_sqs.stub(:queues).and_return(fake_queue_collection)
        fake_queue_collection.stub(:url_for).with(queue_name).and_return(queue_url)
      end

      it 'should create queues that are defined in its internal job name list' do
        #Only one job defined in the spec suite
        fake_queue_collection.should_receive(:create)
        Chore::Queues::SQS.create_queues!
      end

      it 'should delete queues that are defined in its internal job name list' do
        #Only one job defined in the spec suite
        fake_queue.should_receive(:delete)
        Chore::Queues::SQS.delete_queues!
      end
    end
  end
end
