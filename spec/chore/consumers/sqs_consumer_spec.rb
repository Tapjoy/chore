require 'spec_helper'

TestMessage = Struct.new(:handle,:body) do
  def empty?
    false
  end

  # Structs define a to_a behavior that is not compatible with array splatting. Remove it so that
  # [*message] on a struct will behave the same as on a string.
  undef_method :to_a
end

describe Chore::SQSConsumer do
  let(:queue_name) { "test" }
  let(:queues) { double("queues") }
  let(:queue) { double("test_queue") }
  let(:options) { {} }
  let(:consumer) { Chore::SQSConsumer.new(queue_name) }
  let(:message) { TestMessage.new("handle","message body") }

  before do
    AWS::SQS.any_instance.should_receive(:queues).and_return { queues }
    queues.stub(:named) { queue }
    queue.stub(:receive_message) { message }
    queue.stub(:visibility_timeout) { 10 }
  end

  describe "consuming messages" do
    let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, false) }
    let!(:messages_be_unique) { Chore::DuplicateDetector.any_instance.stub(:found_duplicate?).and_return(false) }
    let!(:queue_contain_messages) { queue.stub(:receive_messages).and_return(message) }

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
end
