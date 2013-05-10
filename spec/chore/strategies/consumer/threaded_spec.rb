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

describe Chore::Strategy::ThreadedConsumerStrategy do
  let(:fetcher) { double("fetcher") }
  let(:manager) { double("manager") }
  let(:consumer) { TestConsumer }
  let(:strategy) { Chore::Strategy::ThreadedConsumerStrategy.new(fetcher) }

  before(:each) do
    fetcher.stub(:consumers) { [consumer] }
    fetcher.stub(:manager) { manager }
    Chore.configure do |c| 
      c.queues = ['test'] 
      c.consumer = consumer
      c.batch_size = batch_size
    end
  end

  describe "unfilled batch" do
    let(:batch_size) { 2 }

    it "should queue but not assign the message" do
      consumer.any_instance.should_receive(:consume).and_yield(1, "test")
      strategy.fetch
      strategy.batcher.batch.size.should == 1 
    end
  end

  describe "full batch" do
    let(:batch_size) { 0 }

    it "should assign the batch" do
      manager.should_receive(:assign)
      consumer.any_instance.should_receive(:consume).and_yield(1, "test")
      strategy.fetch
      strategy.batcher.batch.size.should == 0
    end
  end

  describe "2 threads per queue" do
    let(:batch_size) { 2 }
    let(:thread) { double('thread') }

    before do
      Chore.config.threads_per_queue = 2
      thread.stub(:join)
    end

    it "should spawn two threads" do
      # two for threads per queue and one for batcher#schedule
      Thread.should_receive(:new).exactly(3).times { thread }
      strategy.fetch
    end
  end
end
