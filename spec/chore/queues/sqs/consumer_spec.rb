require 'spec_helper'

describe Chore::Queues::SQS::Consumer do
  let(:queue_name) { "test_queue" }
  let(:queue_uri) { Aws::SQS::Types::GetQueueUrlResult.new(queue_url: "http://amazon.sqs.url/queues/#{queue_name}") }
  let(:queue_object) { double(Aws::SQS::Queue, attributes: {'VisibilityTimeout' => rand(10)}) }
  let(:options) { {} }
  let(:consumer) { Chore::Queues::SQS::Consumer.new(queue_name) }
  let(:message) do
    Aws::SQS::Message.new(
      queue_url: queue_uri.queue_url,
      receipt_handle: "receipt_handle",
      data: {
        message_id: 'test message',
        attributes: {
          'ApproximateReceiveCount' => rand(10)
        }
      })
  end
  let(:sqs_empty_message_collection) { double(Aws::SQS::Message::Collection.new([])) }
  let(:sqs) { double(Aws::SQS::Client) }
  let(:backoff_func) { 2 + 2 }
  let(:dupe_detector) { double(Chore::DuplicateDetector) }


  # NOTE(dabrady) Since a message handler is required (but not validated), this convenience method lets us
  # effectively stub the block.
  def consume(&block)
    block = Proc.new{} unless block_given?
    consumer.consume(&block)
  end

  before do
    allow(Aws::SQS::Client).to receive(:new).and_return(sqs)
    allow(sqs).to receive(:get_queue_url).with(:queue_name=>queue_name).and_return(queue_uri)
    allow(sqs).to receive(:receive_message)

    allow(Aws::SQS::Queue).to receive(:new).and_return(queue_object)
    allow(queue_object).to receive(:receive_messages)

    allow(message).to receive(:load)
  end

  describe "consuming messages" do
    before do
      allow(consumer).to receive(:running?).and_return(true, false)
    end

    context "should create objects for interacting with the SQS API" do
      it 'should create an sqs client' do
        expect(Aws::SQS::Client).to receive(:new)
        consume
      end

      it "should only create an sqs client when one doesn't exist" do
        allow(consumer).to receive(:running?).and_return(true, true, true, true, false, true, true)
        expect(Aws::SQS::Client).to receive(:new).exactly(:once)
        consume
      end

      it 'should look up the queue url based on the queue name' do
        expect(sqs).to receive(:get_queue_url).with(:queue_name=>queue_name)
        consume
      end

      it 'should create a queue object' do
        expect(consumer.send(:queue)).to_not be_nil
        consume
      end

      # This seems like it's no longer necessary
      # xit 'should look up the queue based on the queue url' do
      #   # TODO: Fix and reenable this if it's still relevant, otherwise delete
      #   expect(sqs).to receive(:get_queue_uri).with(:queue_name=>queue_name).and_return(queue_uri)
      #   expect(queue_object).to receive(:[]).with(queue_uri).and_return(queue_object)
      #   consume
      # end
    end

    context "should receive a message from the queue" do
      before do
        allow(consumer).to receive(:queue).and_return(queue_object)
      end

      it 'should use the default size of 10 when no queue_polling_size is specified' do
        expect(queue_object).to receive(:receive_messages).with(
          :max_number_of_messages => 10,
          :attribute_names => ['ApproximateReceiveCount']
        ).and_return(message)
        consume
      end

      it 'should respect the queue_polling_size when specified' do
        allow(Chore.config).to receive(:queue_polling_size).and_return(5)
        expect(queue_object).to receive(:receive_messages).with(
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
        allow(queue_object).to receive(:receive_messages).and_return(message)
      end

      it "should check the uniqueness of the message" do
        expect(Chore::DuplicateDetector).to receive(:found_duplicate?)
        consume
      end

      it "should yield the message to the handler block" do
        expect { |b| consumer.consume(&b) }.to yield_with_args('id', 'receipt_handle', queue_name, 10, 'message body', 0)
        # expect { |b| consumer.consume(&b) }.to yield_with_args('id', message.receipt_handle, queue_name, queue_timeout, message.body, message.attributes['ApproximateReceiveCount'].to_i - 1)

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

  describe '#delay' do
    let(:item) { Chore::UnitOfWork.new(message.message_id, message.receipt_handle, message.queue, 60, message.body, 0, consumer) }
    let(:backoff_func) { lambda { |item| 2 } }
    let(:entries) { [{ :id => "id", :receipt_handle => 'receipt_handle', :visibility_timeout => backoff_func.call(item) }] }

    it 'changes the visiblity of the message' do
      # allow(nil).to receive(:data).and_return('response_data') # TODO: Do something about this
      expect(sqs).to receive(:change_message_visibility_batch).with({
        :entries    => entries,
        :queue_url  => queue_uri},
      )
      consumer.delay(item, backoff_func)
    end
  end

  describe '#reset_connection!' do
    it 'should reset the connection after a call to reset_connection!' do
      expect(Aws).to receive(:empty_connection_pools!)
      Chore::Queues::SQS::Consumer.reset_connection!
    end

    it 'should not reset the connection between calls' do
      expect(Aws).to receive(:empty_connection_pools!).once
      # expect(q).to be consumer.send(:queue)
      q = consumer.send(:queue)
      expect(consumer.send(:queue)).to be(q)
    end

    it 'should reconfigure sqs' do
      allow(consumer).to receive(:running?).and_return(true, false)
      allow_any_instance_of(Chore::DuplicateDetector).to receive(:found_duplicate?).and_return(false)

      allow(queue_object).to receive(:receive_messages).and_return(message)
      allow(sqs).to receive(:receive_message).with({:attribute_names=>["ApproximateReceiveCount"], :max_number_of_messages=>10, :queue_uri=>queue_uri})

      consume

      Chore::Queues::SQS::Consumer.reset_connection!
      allow(Aws::SQS::Client).to receive(:new).and_return(sqs)

      expect(consumer).to receive(:running?).and_return(true, false)
      consume
    end
  end
end
