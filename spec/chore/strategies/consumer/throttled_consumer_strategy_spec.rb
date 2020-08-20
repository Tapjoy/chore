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

describe Chore::Strategy::ThrottledConsumerStrategy do
  let(:fetcher) { double("fetcher") }
  let(:manager) { double("manager") }
  let(:thread) {double("thread")}
  let(:consume_queue) { "TestQueue" }
  let(:consumer) { TestConsumer }
  let(:consumer_object) { consumer.new(consume_queue) }
  let(:strategy) { Chore::Strategy::ThrottledConsumerStrategy.new(fetcher) }
  let(:config) { double("config") }
  let(:sized_queue) {double("sized_queue")}
  let(:return_queue) {double("return_queue")}
  let(:work) { double("work") }
  let(:msg) { OpenStruct.new( :id => 1, :body => "test" ) }


  before(:each) do
    allow(fetcher).to receive(:consumers).and_return([consumer])
    allow(fetcher).to receive(:manager).and_return(manager)
    Chore.configure do |c| 
      c.queues = [consume_queue] 
      c.consumer = consumer
    end
  end

  context '#fetch' do
    it 'should call consume, \'@number_of_consumers\' number of times' do
      allow(strategy).to receive(:consume).and_return(thread)
      allow(thread).to receive(:join).and_return(true)
      allow(Chore).to receive(:config).and_return(config)
      allow(config).to receive(:queues).and_return([consume_queue])
      strategy.instance_variable_set(:@consumers_per_queue, 5)
      expect(strategy).to receive(:consume).with(consume_queue).exactly(5).times
      strategy.fetch
    end
  end

  context '#stop!' do
    it 'should should stop itself, and every other consumer' do
      allow(strategy).to receive(:running?).and_return(true)
      strategy.instance_eval('@running = true')
      strategy.instance_variable_set(:@consumers, [consumer_object])
      expect(consumer_object).to receive(:stop)
      strategy.stop!
      expect(strategy.instance_variable_get(:@running)).to eq(false)
    end
  end

  context '#provide_work' do
    it 'should return upto n units of work' do
      n = 2
      strategy.instance_variable_set(:@queue, sized_queue)
      allow(sized_queue).to receive(:size).and_return(10)
      allow(sized_queue).to receive(:pop).and_return(work)
      expect(sized_queue).to receive(:pop).exactly(n).times
      res = strategy.provide_work(n)
      expect(res.size).to eq(n)
      expect(res).to be_a_kind_of(Array)
    end

    it 'should return an empty array if no work is found in the queue' do
      n = 2
      strategy.instance_variable_set(:@queue, sized_queue)
      allow(sized_queue).to receive(:size).and_return(0)
      allow(sized_queue).to receive(:pop).and_return(work)
      expect(sized_queue).to receive(:pop).exactly(0).times
      res = strategy.provide_work(n)
      expect(res.size).to eq(0)
      expect(res).to be_a_kind_of(Array)
    end

    it 'should return units of work from the return queue first' do
      n = 2
      strategy.instance_variable_set(:@return_queue, return_queue)
      allow(return_queue).to receive(:empty?).and_return(false)
      allow(return_queue).to receive(:size).and_return(10)
      allow(return_queue).to receive(:pop).and_return(work)
      expect(return_queue).to receive(:pop).exactly(n).times
      res = strategy.provide_work(n)
      expect(res.size).to eq(n)
      expect(res).to be_a_kind_of(Array)
    end

    it 'should return units of work from all queues if return queue is small' do
      n = 2

      strategy.instance_variable_set(:@return_queue, return_queue)
      allow(return_queue).to receive(:empty?).and_return(false, true)
      allow(return_queue).to receive(:size).and_return(1)
      allow(return_queue).to receive(:pop).and_return(work)
      expect(return_queue).to receive(:pop).once

      strategy.instance_variable_set(:@queue, sized_queue)
      allow(sized_queue).to receive(:size).and_return(1)
      allow(sized_queue).to receive(:pop).and_return(work)
      expect(sized_queue).to receive(:pop).once

      res = strategy.provide_work(n)
      expect(res.size).to eq(n)
      expect(res).to be_a_kind_of(Array)
    end
  end

  context 'return_work' do
    it 'should add it to the internal return queue' do
      strategy.instance_variable_set(:@return_queue, [])
      strategy.send(:return_work, [work])
      strategy.send(:return_work, [work])
      return_queue = strategy.instance_variable_get(:@return_queue)
      expect(return_queue).to eq([work, work])
    end
  end

  context '#consume' do
    it 'should create a consumer object, add it to the list of consumers and start a consumer thread' do
      allow(strategy).to receive(:start_consumer_thread).and_return(true)
      expect(strategy).to receive(:start_consumer_thread)
      strategy.send(:consume, consume_queue)
      expect(strategy.instance_variable_get(:@consumers)).to be_a_kind_of(Array)
      expect(strategy.instance_variable_get(:@consumers).first).to be_a_kind_of(TestConsumer)
    end
  end

  context '#start_consumer_thread' do
    let(:thread) { double('thread') }

    it 'should create a thread' do
      allow(Thread).to receive(:new).and_return(thread)
      res = strategy.send(:start_consumer_thread, consumer_object)
      expect(res).to eq(thread)
    end
  end

  context '#create_work_units' do
    it 'should create an unit of work from what the consumer gets, and adds it to the internal queue' do
      strategy.instance_variable_set(:@queue, [])
      res = strategy.send(:create_work_units, consumer_object)
      internal_queue = strategy.instance_variable_get(:@queue)
      expect(internal_queue).to be_a_kind_of(Array)
      expect(internal_queue.first).to be_a_kind_of(Chore::UnitOfWork)
      expect(internal_queue.first.id).to eq(msg)
    end
  end
end
