require 'spec_helper'

describe Chore::Queues::SQS::Consumer do
  include_context 'fake objects'

  let(:options) { {} }
  let(:consumer) { Chore::Queues::SQS::Consumer.new(queue_name) }
  let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']} }
  let(:backoff_func) { Proc.new { 2 + 2 } }

  let(:receive_message_result) { Aws::SQS::Message::Collection.new([message], size: 1) }

  let(:message) do
      Aws::SQS::Message.new(
      message_id: 'message id',
      receipt_handle: "receipt_handle",
      body: job.to_json,
      data: job,
      queue: queue,
      queue_url: queue_url,
    )
  end

  # Since a message handler is required (but not validated), this convenience method lets us
  # effectively stub the block.
  def consume(&block)
    block = Proc.new{} unless block_given?
    consumer.consume(&block)
  end

  before do
    allow(Aws::SQS::Client).to receive(:new).and_return(sqs)
    allow(Aws::SQS::Queue).to receive(:new).and_return(queue)
    allow(queue).to receive(:receive_messages).and_return(receive_message_result)
    allow(message).to receive(:attributes).and_return({ 'ApproximateReceiveCount' => rand(10) })
  end

  describe "consuming messages" do
    before do
      allow(consumer).to receive(:running?).and_return(true, false)
    end

    context "should create objects for interacting with the SQS API" do
      it 'should create an sqs client' do
        expect(queue).to receive(:receive_messages)
        consume
      end

      it "should only create an sqs client when one doesn't exist" do
        allow(consumer).to receive(:running?).and_return(true, true, true, true, false, true, true)
        expect(Aws::SQS::Client).to receive(:new).exactly(:once)
        consume
      end

      it 'should look up the queue url based on the queue name' do
        expect(sqs).to receive(:get_queue_url).with(queue_name: queue_name)
        consume
      end

      it 'should create a queue object' do
        expect(consumer.send(:queue)).to_not be_nil
        consume
      end
    end

    context "should receive a message from the queue" do
      it 'should use the default size of 10 when no queue_polling_size is specified' do
        expect(queue).to receive(:receive_messages).with(
          :max_number_of_messages => 10,
          :attribute_names => ['ApproximateReceiveCount']
        ).and_return(message)
        consume
      end

      it 'should respect the queue_polling_size when specified' do
        allow(Chore.config).to receive(:queue_polling_size).and_return(5)
        expect(queue).to receive(:receive_messages).with(
          :max_number_of_messages => 5,
          :attribute_names => ['ApproximateReceiveCount']
        )
        consume
      end
    end

    context 'with no messages' do
      before do
        allow(consumer).to receive(:handle_messages).and_return([])
      end

      it 'should sleep' do
        expect(consumer).to receive(:sleep).with(1)
        consume
      end
    end

    context 'with messages' do
      before do
        allow(consumer).to receive(:duplicate_message?).and_return(false)
        allow(queue).to receive(:receive_messages).and_return(message)
      end

      it "should check the uniqueness of the message" do
        expect(consumer).to receive(:duplicate_message?)
        consume
      end

      it "should yield the message to the handler block" do
        expect { |b| consume(&b) }
          .to yield_with_args(
                message.message_id,
                message.receipt_handle,
                queue_name,
                queue.attributes['VisibilityTimeout'].to_i,
                message.body,
                message.attributes['ApproximateReceiveCount'].to_i - 1
              )
      end

      it 'should not sleep' do
        expect(consumer).to_not receive(:sleep)
        consume
      end

      context 'with duplicates' do
        before do
          allow(consumer).to receive(:duplicate_message?).and_return(true)
        end

        it 'should not yield for a dupe message' do
          expect {|b| consume(&b) }.not_to yield_control
        end
      end
    end
  end

  describe "completing work" do
    it 'deletes the message from the queue' do
      expect(queue).to receive(:delete_messages).with(entries: [{id: message.message_id, receipt_handle: message.receipt_handle}])
      consumer.complete(message.message_id, message.receipt_handle)
    end
  end

  describe '#delay' do
    let(:item) { Chore::UnitOfWork.new(message.message_id, message.receipt_handle, message.queue, 60, message.body, 0, consumer) }
    let(:entries) do
      [
        { id: item.id, receipt_handle: item.receipt_handle, visibility_timeout: backoff_func.call(item) },
      ]
    end

    it 'changes the visiblity of the message' do
      expect(queue).to receive(:change_message_visibility_batch).with(entries: entries)
      consumer.delay(item, backoff_func)
    end
  end

  describe '#reset_connection!' do
    it 'should reset the connection after a call to reset_connection!' do
      expect(Aws).to receive(:empty_connection_pools!)
      Chore::Queues::SQS::Consumer.reset_connection!
      consumer.send(:queue)
    end

    it 'should not reset the connection between calls' do
      expect(Aws).to receive(:empty_connection_pools!).once
      q = consumer.send(:queue)
      expect(consumer.send(:queue)).to be(q)
    end

    it 'should reconfigure sqs' do
      allow(consumer).to receive(:running?).and_return(true, false)
      allow_any_instance_of(Chore::DuplicateDetector).to receive(:found_duplicate?).and_return(false)

      allow(queue).to receive(:receive_messages).and_return(message)
      allow(sqs).to receive(:receive_message).with({:attribute_names=>["ApproximateReceiveCount"], :max_number_of_messages=>10, :queue_url=>queue_url})

      consume

      Chore::Queues::SQS::Consumer.reset_connection!
      allow(Aws::SQS::Client).to receive(:new).and_return(sqs)

      expect(consumer).to receive(:running?).and_return(true, false)
      consume
    end
  end
end
