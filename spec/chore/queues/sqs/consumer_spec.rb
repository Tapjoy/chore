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
    AWS::SQS.stub(:new).and_return(sqs)
    sqs.stub(:queues).and_return { queues }
     
    queues.stub(:url_for) { queue_url }
    queues.stub(:[]) { queue }
    queue.stub(:receive_message) { message }
    pool.stub(:empty!) { nil }
  end

  describe "consuming messages" do
    let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, false) }
    let!(:messages_be_unique) { Chore::DuplicateDetector.any_instance.stub(:found_duplicate?).and_return(false) }
    let!(:queue_contain_messages) { queue.stub(:receive_messages).and_return(message) }

    it 'should configure sqs' do
      Chore.config.stub(:aws_access_key).and_return('key')
      Chore.config.stub(:aws_secret_key).and_return('secret')

      AWS::SQS.should_receive(:new).with(
        :access_key_id => 'key',
        :secret_access_key => 'secret',
        :logger => Chore.logger,
        :log_level => :debug
      ).and_return(sqs)
      consumer.consume
    end

    it 'should not configure sqs multiple times' do
      consumer.stub(:running?).and_return(true, true, false)

      AWS::SQS.should_receive(:new).once.and_return(sqs)
      consumer.consume
    end

    it 'should look up the queue url based on the queue name' do
      queues.should_receive(:url_for).with('test').and_return(queue_url)
      consumer.consume
    end

    it 'should look up the queue based on the queue url' do
      queues.should_receive(:[]).with(queue_url).and_return(queue)
      consumer.consume
    end

    context "should receive a message from the queue" do

      it 'should use the default size of 10 when no queue_polling_size is specified' do
        queue.should_receive(:receive_messages).with(:limit => 10, :attributes => [:receive_count])
        consumer.consume
      end

      it 'should respect the queue_polling_size when specified' do
        Chore.config.stub(:queue_polling_size).and_return(5)
        queue.should_receive(:receive_messages).with(:limit => 5, :attributes => [:receive_count])
        consumer.consume
      end
    end

    it "should check the uniqueness of the message" do
      Chore::DuplicateDetector.any_instance.should_receive(:found_duplicate?).with(message_data).and_return(false)
      consumer.consume
    end

    it "should yield the message to the handler block" do
      expect { |b| consumer.consume(&b) }.to yield_with_args('handle', queue_name, 10, 'message body', 0)
    end

    it 'should not yield for a dupe message' do
      Chore::DuplicateDetector.any_instance.should_receive(:found_duplicate?).with(message_data).and_return(true)
      expect {|b| consumer.consume(&b) }.not_to yield_control
    end

    context 'with no messages' do
      let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, true, false) }
      let!(:queue_contain_messages) { queue.stub(:receive_messages).and_return(message, nil) }

      it 'should sleep' do
        consumer.should_receive(:sleep).with(1)
        consumer.consume
      end
    end

    context 'with messages' do
      let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, true, false) }
      let!(:queue_contain_messages) { queue.stub(:receive_messages).and_return(message, message) }

      it 'should not sleep' do
        consumer.should_not_receive(:sleep)
        consumer.consume
      end
    end
  end

  describe '#reset_connection!' do
    it 'should reset the connection after a call to reset_connection!' do
      AWS::Core::Http::ConnectionPool.stub(:pools).and_return([pool])
      pool.should_receive(:empty!)
      Chore::Queues::SQS::Consumer.reset_connection!
      consumer.send(:queue)
    end

    it 'should not reset the connection between calls' do
      sqs = consumer.send(:queue)
      sqs.should be consumer.send(:queue)
    end

    it 'should reconfigure sqs' do
      consumer.stub(:running?).and_return(true, false)
      Chore::DuplicateDetector.any_instance.stub(:found_duplicate?).and_return(false)

      queue.stub(:receive_messages).and_return(message)
      consumer.consume

      Chore::Queues::SQS::Consumer.reset_connection!
      AWS::SQS.should_receive(:new).and_return(sqs)

      consumer.stub(:running?).and_return(true, false)
      consumer.consume
    end
  end
end
