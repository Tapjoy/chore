require 'spec_helper'

describe Chore::Queues::SQS::Consumer do
  let(:queue_name) { "test" }
  let(:queues) { double("queues") }
  let(:queue) { double("test_queue") }
  let(:options) { {} }
  let(:consumer) { Chore::Queues::SQS::Consumer.new(queue_name) }
  let(:message) { TestMessage.new("handle","message body") }
  let(:pool) { double("pool") }

  before do
    AWS::SQS.any_instance.stub(:queues).and_return { queues }
    queues.stub(:named) { queue }
    queue.stub(:receive_message) { message }
    queue.stub(:visibility_timeout) { 10 }
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
      ).and_call_original
      consumer.consume
    end

    it 'should not configure sqs multiple times' do
      consumer.stub(:running?).and_return(true, true, false)

      AWS::SQS.should_receive(:new).once.and_call_original
      consumer.consume
    end

    it "should receive a message from the queue" do
      queue.should_receive(:receive_messages)
      consumer.consume
    end

    it "should check the uniqueness of the message" do
      Chore::DuplicateDetector.any_instance.should_receive(:found_duplicate?).with(message).and_return(false)
      consumer.consume
    end

    it "should yield the message to the handler block" do
      expect { |b| consumer.consume(&b).to yield_control(message) }
    end

    it 'should not yield for a dupe message' do
      Chore::DuplicateDetector.any_instance.should_receive(:found_duplicate?).with(message).and_return(true)
      expect {|b| consumer.consume(&b) }.not_to yield_control
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
      AWS::SQS.should_receive(:new).and_call_original

      consumer.stub(:running?).and_return(true, false)
      consumer.consume
    end
  end
end
