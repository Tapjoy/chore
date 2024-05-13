require 'spec_helper'

describe Chore::Strategy::SingleConsumerStrategy do
  let(:fetcher) { double("fetcher") }
  let(:manager) { double("manager") }
  let(:consumer) { double("consumer") }
  let(:test_queues) { ["test-queue"] }
  let(:strategy) { Chore::Strategy::SingleConsumerStrategy.new(fetcher) }
  let(:received_timeout) {Time.now}

  before do
    fetcher.stub(:manager) { manager }
    Chore.config.stub(:queues).and_return(test_queues)
    Chore.config.stub(:consumer).and_return(consumer)

  end

  it "should consume and then assign a message" do
    allow(Time).to receive(:now).and_return(received_timeout)
    consumer.should_receive(:new).with(test_queues.first).and_return(consumer)
    consumer.should_receive(:consume).and_yield(1, nil, 'test-queue', 60, "test", 0, received_timeout)
    manager.should_receive(:assign).with(Chore::UnitOfWork.new(1, nil, 'test-queue', 60, "test", 0, consumer, nil, nil, received_timeout))
    strategy.fetch
  end
end
