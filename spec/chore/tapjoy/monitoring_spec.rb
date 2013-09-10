require 'spec_helper'

require 'chore/tapjoy/monitoring'

describe Chore::Tapjoy::Monitoring do

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

  before(:each) do
    Watcher::Publisher::Statsd.stub(:new)
    Chore.config.statsd = {:default_attributes => {:bloo=>"blah"}}

    Chore::Tapjoy::Monitoring.register_tapjoy_handlers!
  end

  after(:each) do
    Chore.clear_hooks!
  end

  let(:worker)       { Chore::Worker.new }
  let(:consumer)     { double('consumer') }
  let(:job_args)     { [1,2,'3'] }
  let(:job)          { SimpleJob.job_hash(job_args) }
  let(:breaking_job) { BreakingJob.job_hash(job_args) }
  let(:rejected_job) { RejectedJob.job_hash(job_args) }
  let(:metric)       { double('metric', :increment => true) }

  it 'should add default metric values to metrics' do
    work = []
    work << Chore::UnitOfWork.new('1', Chore::JsonEncoder.encode(job), 0, consumer)
    consumer.should_receive(:complete).with('1')
    Watcher::Metric.should_receive(:new).with("start", attributes: hash_including( bloo: "blah", stat: "chore", state: "started", queue: "SimpleJob" )) { metric }
    Watcher::Metric.should_receive(:new).with("finish", attributes: hash_including( bloo: "blah", stat: "chore", state: "completed", queue: "SimpleJob" )) { metric }
    Chore::Worker.start(work)
  end

  it 'should process after message hooks with success or failure' do
    work = []
    work << Chore::UnitOfWork.new('1', Chore::JsonEncoder.encode(job), 0, consumer)
    work << Chore::UnitOfWork.new('2', Chore::JsonEncoder.encode(breaking_job), 0, consumer)
    work << Chore::UnitOfWork.new('4', Chore::JsonEncoder.encode(rejected_job), 0, consumer)
    consumer.should_receive(:complete).with('1')
    consumer.should_receive(:reject).with('4')

    Watcher::Metric.should_receive(:new).with("start", attributes: hash_including( stat: "chore", state: "started", queue: "SimpleJob" )) { metric }
    Watcher::Metric.should_receive(:new).with("finish", attributes: hash_including( stat: "chore", state: "completed", queue: "SimpleJob" )) { metric }

    Watcher::Metric.should_receive(:new).with("start", attributes: hash_including( stat: "chore", state: "started", queue: "BreakingJob" )) { metric }
    Watcher::Metric.should_receive(:new).with("finish", attributes: hash_including( stat: "chore", state: "failed", queue: "BreakingJob" )) { metric }

    Watcher::Metric.should_receive(:new).with("start", attributes: hash_including( stat: "chore", state: "started", queue: "RejectedJob" )) { metric }
    Watcher::Metric.should_receive(:new).with("finish", attributes: hash_including( stat: "chore", state: "rejected", queue: "RejectedJob" )) { metric }

    Chore::Worker.start(work)
  end
end
