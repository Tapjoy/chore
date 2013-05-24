require 'spec_helper'

describe Chore::Queues::SQS::LockingConsumer do
  let(:sqs) { double("sqs") }
  let(:queue_name) { "test" }
  let(:queues) { double("queues") }
  let(:queue) { double("test_queue") }
  let(:options) { {} }
  let(:consumer) { Chore::Queues::SQS::LockingConsumer.new(queue_name) }
  let(:message) { TestMessage.new("handle","message body") }
  let(:zk) { double('zk') }
  let(:semaphore) { double("semaphore") }
  let(:max_leases) { 1 }
  let(:enabled) { true }

  before do
    AWS::SQS.stub(:new) { sqs }
    sqs.stub(:queues).and_return { queues }
    queues.stub(:named) { queue }
    queue.stub(:receive_message) { message }
    queue.stub(:visibility_timeout) { 10 }
    ZK.stub(:new) { zk }
    Chore::Semaphore.stub(:new) { semaphore }
    zk.stub(:close!)
    consumer.stub(:max_leases) { max_leases }
  end

  before(:each) do
    Chore::Queues::SQS::LockingConsumer.class_variable_set(:@@zk, zk)
  end

  after(:each) do 
    Chore::Queues::SQS::LockingConsumer.class_variable_set(:@@zk, nil)
  end

  describe "has free leases" do
    let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, false) }
    let!(:messages_be_unique) { Chore::DuplicateDetector.any_instance.stub(:found_duplicate?).and_return(false) }
    let!(:queue_contain_messages) { queue.stub(:receive_messages).and_return(message) }
    it "should acquire a lock" do
      semaphore.should_receive(:acquire).and_yield
      consumer.consume 
    end
  end

  describe "doesn't require leases" do
    let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, false) }
    let!(:messages_be_unique) { Chore::DuplicateDetector.any_instance.stub(:found_duplicate?).and_return(false) }
    let!(:queue_contain_messages) { queue.stub(:receive_messages).and_return(message) }
    let(:max_leases) { 0 }

    it "should not acquire a lock" do
      semaphore.should_not_receive(:acquire)
      consumer.consume
    end
  end

  describe "disabled job" do
    let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, false) }
    let(:max_leases) { -1 }

    it "should not do anything" do
      consumer.should_not_receive(:requires_lock?)
      consumer.should_not_receive(:handle_messages)
      consumer.consume
    end
  end

end
