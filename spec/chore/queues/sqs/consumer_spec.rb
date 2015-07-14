require 'spec_helper'

describe Chore::Queues::SQS::Consumer do
  let(:queue_name) { "test" }
  let(:queue_url) { "test_url" }
  let(:queues) { double("queues") }
  let(:queue) { double("test_queue", :visibility_timeout=>10, :url=>"test_queue", :name=>"test_queue") }
  let(:options) { {} }
  let(:consumer) { Chore::Queues::SQS::Consumer.new(queue_name) }
  let(:message) { TestMessage.new("handle",queue, "message body", 1) }
  let(:message_data) {{:id=>message.id, :queue=>message.queue.url, :visibility_timeout=>message.queue.visibility_timeout}}
  let(:pool) { double("pool") }
  let(:sqs) { double('AWS::SQS') }

  before do
    allow(AWS::SQS).to receive(:new).and_return(sqs)
    allow(sqs).to receive(:queues) { queues }

    allow(queues).to receive(:url_for) { queue_url }
    allow(queues).to receive(:[]) { queue }
    allow(queue).to receive(:receive_message) { message }
    allow(pool).to receive(:empty!) { nil }
  end

  describe "consuming messages" do
    let!(:consumer_run_for_one_message) { allow(consumer).to receive(:running?).and_return(true, false) }
    let!(:messages_be_unique) { allow_any_instance_of(Chore::DuplicateDetector).to receive(:found_duplicate?).and_return(false) }
    let!(:queue_contain_messages) { allow(queue).to receive(:receive_messages).and_return(message) }

    it 'should configure sqs' do
      allow(Chore.config).to receive(:aws_access_key).and_return('key')
      allow(Chore.config).to receive(:aws_secret_key).and_return('secret')

      expect(AWS::SQS).to receive(:new).with(
        :access_key_id => 'key',
        :secret_access_key => 'secret',
        :logger => Chore.logger,
        :log_level => :debug
      ).and_return(sqs)
      consumer.consume
    end

    it 'should not configure sqs multiple times' do
      allow(consumer).to receive(:running?).and_return(true, true, false)

      expect(AWS::SQS).to receive(:new).once.and_return(sqs)
      consumer.consume
    end

    it 'should look up the queue url based on the queue name' do
      expect(queues).to receive(:url_for).with('test').and_return(queue_url)
      consumer.consume
    end

    it 'should look up the queue based on the queue url' do
      expect(queues).to receive(:[]).with(queue_url).and_return(queue)
      consumer.consume
    end

    context "should receive a message from the queue" do

      it 'should use the default size of 10 when no queue_polling_size is specified' do
        expect(queue).to receive(:receive_messages).with(:limit => 10, :attributes => [:receive_count])
        consumer.consume
      end

      it 'should respect the queue_polling_size when specified' do
        allow(Chore.config).to receive(:queue_polling_size).and_return(5)
        expect(queue).to receive(:receive_messages).with(:limit => 5, :attributes => [:receive_count])
        consumer.consume
      end
    end

    it "should check the uniqueness of the message" do
      allow_any_instance_of(Chore::DuplicateDetector).to receive(:found_duplicate?).with(message_data).and_return(false)
      consumer.consume
    end

    it "should yield the message to the handler block" do
      expect { |b| consumer.consume(&b) }.to yield_with_args('handle', queue_name, 10, 'message body', 0)
    end

    it 'should not yield for a dupe message' do
      allow_any_instance_of(Chore::DuplicateDetector).to receive(:found_duplicate?).with(message_data).and_return(true)
      expect {|b| consumer.consume(&b) }.not_to yield_control
    end

    context 'with no messages' do
      let!(:consumer_run_for_one_message) { allow(consumer).to receive(:running?).and_return(true, true, false) }
      let!(:queue_contain_messages) { allow(queue).to receive(:receive_messages).and_return(message, nil) }

      it 'should sleep' do
        expect(consumer).to receive(:sleep).with(1)
        consumer.consume
      end
    end

    context 'with messages' do
      let!(:consumer_run_for_one_message) { allow(consumer).to receive(:running?).and_return(true, true, false) }
      let!(:queue_contain_messages) { allow(queue).to receive(:receive_messages).and_return(message, message) }

      it 'should not sleep' do
        expect(consumer).to_not receive(:sleep)
        consumer.consume
      end
    end
  end

  describe '#reset_connection!' do
    it 'should reset the connection after a call to reset_connection!' do
      expect(AWS::Core::Http::ConnectionPool).to receive(:pools).and_return([pool])
      expect(pool).to receive(:empty!)
      Chore::Queues::SQS::Consumer.reset_connection!
      consumer.send(:queue)
    end

    it 'should not reset the connection between calls' do
      sqs = consumer.send(:queue)
      expect(sqs).to be consumer.send(:queue)
    end

    it 'should reconfigure sqs' do
      allow(consumer).to receive(:running?).and_return(true, false)
      allow_any_instance_of(Chore::DuplicateDetector).to receive(:found_duplicate?).and_return(false)

      allow(queue).to receive(:receive_messages).and_return(message)
      consumer.consume

      Chore::Queues::SQS::Consumer.reset_connection!
      allow(AWS::SQS).to receive(:new).and_return(sqs)

      expect(consumer).to receive(:running?).and_return(true, false)
      consumer.consume
    end
  end
end
