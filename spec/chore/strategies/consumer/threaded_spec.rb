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

describe Chore::Strategy::Batcher do
  let(:batch_size) { 5 }
  let(:callback) { double("callback") }
  subject do
    batcher = Chore::Strategy::Batcher.new(batch_size)
    batcher.callback = callback
    batcher
  end

  context 'with no items' do
    it 'should not be ready' do
      subject.should_not be_ready
    end

    it 'should not invoke the callback when executed' do
      callback.should_not_receive(:call)
      subject.execute
    end

    it 'should not invoke the callback when force-executed' do
      callback.should_not_receive(:call)
      subject.execute(true)
    end

    it 'should not invoke callback when adding a new item' do
      callback.should_not_receive(:call)
      subject.add('test')
    end
  end

  context 'with partial batch completed' do
    let(:batch) { ['test'] * 3 }

    before(:each) do
      subject.batch = batch.dup
    end

    it 'should not be ready' do
      subject.should_not be_ready
    end

    it 'should not invoke callback when executed' do
      callback.should_not_receive(:call)
      subject.execute
    end

    it 'should invoke callback when force-executed' do
      callback.should_receive(:call).with(batch)
      subject.execute(true)
    end

    it 'should invoke callback when add completes the batch' do
      subject.add('test')
      callback.should_receive(:call).with(['test'] * 5)
      subject.add('test')
    end
  end

  context 'with batch completed' do
    let(:batch) { ['test'] * 5 }

    before(:each) do
      subject.batch = batch.dup
    end

    it 'should be ready' do
      subject.should be_ready
    end

    it 'should invoke callback when executed' do
      callback.should_receive(:call).with(batch)
      subject.execute
    end

    it 'should invoke callback when force-executed' do
      callback.should_receive(:call).with(batch)
      subject.execute(true)
    end

    it 'should invoke callback with subset-only when added to' do
      callback.should_receive(:call).with(['test'] * 5)
      subject.add('test')
    end

    it 'should leave remaining batch when added to' do
      callback.stub(:call)
      subject.add('test')
      subject.batch.should == ['test']
    end
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
      consumer.any_instance.should_receive(:consume).and_yield(1, 'test-queue', "test", 0)
      strategy.fetch
      strategy.batcher.batch.size.should == 1

      work = strategy.batcher.batch[0]
      work.id.should == 1
      work.queue_name.should == 'test-queue'
      work.message.should == "test"
      work.previous_attempts.should == 0
      work.current_attempt.should == 1
    end
  end

  describe "full batch" do
    let(:batch_size) { 1 }

    it "should assign the batch" do
      manager.should_receive(:assign)
      consumer.any_instance.should_receive(:consume).and_yield(1, 'test-queue', "test", 0)
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

  describe "non-existent queue" do
    let(:bad_consumer) { NoQueueConsumer }
    let(:fetcher) { double("fetcher") }
    let(:strategy) { Chore::Strategy::ThreadedConsumerStrategy.new(fetcher) }
    let(:batch_size) { 2 }

    before do
      fetcher.stub(:consumers) { [bad_consumer] }
      Chore.configure do |c| 
        c.queues = ['test'] 
        c.consumer = bad_consumer
        c.batch_size = batch_size
        c.threads_per_queue = 1
      end
    end

    it "should shut down when a queue doesn't exist" do
      manager.should_receive(:shutdown!)
      strategy.fetch
    end
  end
end
