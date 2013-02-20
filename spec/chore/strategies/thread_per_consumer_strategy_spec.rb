require 'spec_helper'

class TestConsumer < Chore::Consumer
  def initialize(queue_name, opts={})
  end

  def consume
    # just something that looks like an SQS message
    msg = OpenStruct.new( :id => 1, :body => "test" )
    yield msg if block_given?
  end
end

describe Chore::ThreadPerConsumerStrategy do
  let(:fetcher) { double("fetcher") }
  let(:manager) { double("manager") }
  let(:consumer) { TestConsumer }
  let(:strategy) { Chore::ThreadPerConsumerStrategy.new(fetcher) }

  before(:each) do
    fetcher.stub(:consumers) { [consumer] }
    fetcher.stub(:manager) { manager }
    Chore.configure do |c| 
      c.queues = ['test'] 
      c.consumer = consumer
      c.batch_size = batch_size
    end
    consumer.any_instance.should_receive(:consume).and_yield(1, "test")
  end

  describe "unfilled batch" do
    let(:batch_size) { 2 }

    it "should queue but not assign the message" do
      strategy.fetch
      strategy.batch.size.should == 1 
    end
  end

  describe "full batch" do
    let(:batch_size) { 0 }

    it "should assign the batch" do
      manager.should_receive(:assign)
      strategy.fetch
      strategy.batch.size.should == 0
    end
  end
end
