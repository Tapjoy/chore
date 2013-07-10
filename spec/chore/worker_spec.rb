require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'watcher/client'
require 'chore/tapjoy/monitoring'

class SimpleJob
  include Chore::Job
  queue_options :name => 'test', :publisher => FakePublisher

  def perform(*args)
    return args
  end
end

class BreakingJob
  include Chore::Job
  queue_options :name => 'test', :publisher => FakePublisher

  def perform(*args)
    raise "test"
  end
end

class RejectedJob
  include Chore::Job
  queue_options :name => 'test', :publisher => FakePublisher

  def perform(*args)
    raise Chore::Job::RejectMessageException
  end
end

describe Chore::Worker do
  let(:consumer) { double('consumer') }
  let(:job_args) { [1,2,'3'] }
  let(:job) { SimpleJob.job_hash(job_args) }
  let(:breaking_job) { BreakingJob.job_hash(job_args) }
  let(:rejected_job) { RejectedJob.job_hash(job_args) }
  let(:metric) { double('metric') }

  before do
    metric.stub(:increment)
  end

  after do
    Chore.clear_hooks!
  end

  it 'should use a default encoder' do
    worker = Chore::Worker.new
    worker.options[:encoder].should == Chore::JsonEncoder
  end

  it 'should process a single job' do
    work = Chore::UnitOfWork.new('1', Chore::JsonEncoder.encode(job), consumer)
    SimpleJob.should_receive(:perform).with(*job_args)
    consumer.should_receive(:complete).with('1')
    w = Chore::Worker.new(work)
    w.start
  end

  it 'should process multiple jobs' do
    work = []
    10.times do |i|
      work << Chore::UnitOfWork.new(i, Chore::JsonEncoder.encode(job), consumer)
    end
    SimpleJob.should_receive(:perform).exactly(10).times
    consumer.should_receive(:complete).exactly(10).times
    Chore::Worker.start(work)
  end

  context 'when configured for Watcher integration' do
    before :all do
      Watcher::Publisher::Statsd.stub(:new)
      Chore.config.statsd = {:defaults => {:bloo=>"blah"}}
    end

    before :each do
      Chore::Tapjoy::Monitoring.register_tapjoy_handlers!
    end

    it 'should add default metric values to metrics' do
      work = []
      work << Chore::UnitOfWork.new('1', Chore::JsonEncoder.encode(job), consumer)
      consumer.should_receive(:complete).with('1')
      Watcher::Metric.should_receive(:new).with("finished", attributes: hash_including( bloo: "blah", state: "completed", queue: "SimpleJob" )) { metric }
      Chore::Worker.start(work)
    end

    it 'should process after message hooks with success or failure' do
      work = []
      work << Chore::UnitOfWork.new('1', Chore::JsonEncoder.encode(job), consumer)
      work << Chore::UnitOfWork.new('2', Chore::JsonEncoder.encode(breaking_job), consumer) 
      work << Chore::UnitOfWork.new('4', Chore::JsonEncoder.encode(rejected_job), consumer) 
      consumer.should_receive(:complete).with('1')
      consumer.should_receive(:reject).with('4')
      Watcher::Metric.should_receive(:new).with("finished", attributes: hash_including( state: "completed", queue: "SimpleJob" )) { metric }
      Watcher::Metric.should_receive(:new).with("finished", attributes: hash_including( state: "failed", queue: "BreakingJob" )) { metric }
      Watcher::Metric.should_receive(:new).with("finished", attributes: hash_including( state: "rejected", queue: "RejectedJob" )) { metric }
      Chore::Worker.start(work)
    end
  end

  it 'should set the status to the current running job' do
    work = Chore::UnitOfWork.new('1',Chore::JsonEncoder.encode(job), consumer)
    SimpleJob.should_receive(:perform).with(*job_args)
    consumer.should_receive(:complete)
    w = Chore::Worker.new(work)
    w.should_receive(:status=).with(hash_including('class'=>SimpleJob.name))
    w.start
  end

  describe 'with errors' do
    let(:job) { "Not-A-Valid-Json-String" }

    it 'should fail cleanly with a badly formatted message' do
      work = Chore::UnitOfWork.new(2,job,consumer)
      consumer.should_not_receive(:complete)
      Chore.should_receive(:run_hooks_for).with(:on_failure, job, anything())
      Chore::Worker.start(work)
    end
  end
end
