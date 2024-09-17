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

class NoQueueConsumer < Chore::Consumer
  def initialize(queue_name, opts={})
    raise Chore::TerribleMistake
  end

  def consume
  end
end

describe Chore::Strategy::ThreadedConsumerStrategy do
  let(:fetcher) { double("fetcher") }
  let(:manager) { double("manager") }
  let(:consumer) { TestConsumer }
  let(:strategy) { Chore::Strategy::ThreadedConsumerStrategy.new(fetcher) }

  before(:each) do
    allow(fetcher).to receive(:consumers) { [consumer] }
    allow(fetcher).to receive(:manager) { manager }
    Chore.configure do |c|
      c.queues = ['test']
      c.consumer = consumer
      c.batch_size = batch_size
    end
  end

  describe "unfilled batch" do
    let(:batch_size) { 2 }

    it "should queue but not assign the message" do
      allow_any_instance_of(consumer).to receive(:consume).and_yield(1, nil, 'test-queue', 60, "test", 0, Time.now)
      strategy.fetch
      expect(strategy.batcher.batch.size).to eq(1)

      work = strategy.batcher.batch[0]
      expect(work.id).to eq(1)
      expect(work.queue_name).to eq('test-queue')
      expect(work.queue_timeout).to eq(60)
      expect(work.message).to eq("test")
      expect(work.previous_attempts).to eq(0)
      expect(work.current_attempt).to eq(1)
      expect(work.created_at).not_to be_nil
    end
  end

  describe "full batch" do
    let(:batch_size) { 1 }

    it "should assign the batch" do
      expect(manager).to receive(:assign)
      allow_any_instance_of(consumer).to receive(:consume).and_yield(1, nil, 'test-queue', 60, "test", 0, Time.now)
      strategy.fetch
      expect(strategy.batcher.batch.size).to eq(0)
    end
  end

  describe "2 threads per queue" do
    let(:batch_size) { 2 }
    let(:thread) { double('thread') }

    before do
      Chore.config.threads_per_queue = 2
      allow(thread).to receive(:join)
    end

    it "should spawn two threads" do
      # two for threads per queue and one for batcher#schedule
      expect(Thread).to receive(:new).exactly(3).times { thread }
      strategy.fetch
    end
  end

  describe "non-existent queue" do
    let(:bad_consumer) { NoQueueConsumer }
    let(:fetcher) { double("fetcher") }
    let(:strategy) { Chore::Strategy::ThreadedConsumerStrategy.new(fetcher) }
    let(:batch_size) { 2 }

    before do
      allow(fetcher).to receive(:consumers) { [bad_consumer] }
      Chore.configure do |c|
        c.queues = ['test']
        c.consumer = bad_consumer
        c.batch_size = batch_size
        c.threads_per_queue = 1
      end
    end

    it "should shut down when a queue doesn't exist" do
      expect(manager).to receive(:shutdown!)
      strategy.fetch
    end
  end
end
