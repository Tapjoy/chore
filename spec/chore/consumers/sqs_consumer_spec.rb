require 'spec_helper'

describe Chore::SQSConsumer do
  let(:queue_name) { "test" }
  let(:queues) { double("queues") }
  let(:queue) { double("test_queue") }
  let(:options) { {} }
  let(:consumer) { Chore::SQSConsumer.new(queue_name) }
  let(:message) { "message" }

  before do
    AWS::SQS.any_instance.should_receive(:queues).and_return { queues }
    queues.stub(:named) { queue }
    queue.stub(:receive_message) { message }
  end

  describe "consuming messages" do
    it "should receive a message from the queue" do
      consumer.stub(:loop_forever?).and_return(true, false)
      queue.should_receive(:receive_messages)
      consumer.consume 
    end
  end
end
