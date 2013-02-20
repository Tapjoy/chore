require 'spec_helper'

describe Chore::SingleConsumerStrategy do
  let(:fetcher) { double("fetcher") }
  let(:manager) { double("manager") }
  let(:consumer) { double("consumer") }
  let(:strategy) { Chore::SingleConsumerStrategy.new(fetcher) }

  before do
    fetcher.stub(:consumers) { [consumer] }
    fetcher.stub(:manager) { manager }
  end

  it "should consume and then assign a message" do
    consumer.should_receive(:consume).and_yield(1, "test")
    manager.should_receive(:assign)
    strategy.fetch
  end
end
