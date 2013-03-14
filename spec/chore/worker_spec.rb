require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

class SimpleJob
  include Chore::Job
  queue_options :name => 'test', :publisher => FakePublisher

  def perform(*args)
    return args
  end
end

class TimeoutJob
  include Chore::Job
  queue_options :name => 'test', :publisher => FakePublisher, :timeout => 0.1

  def perform(*args)
    sleep(0.2)
  end
end

describe Chore::Worker do
  let(:consumer) { double('consumer') }
  let(:job_args) { [1,2,'3'] }
  let(:job) { SimpleJob.job_hash(job_args) }
  let(:timeout_job) { TimeoutJob.job_hash(job_args) }

  it 'should use a default encoder' do
    worker = Chore::Worker.new
    worker.options[:encoder].should == Chore::JsonEncoder
  end

  it 'should process a single job' do
    work = Chore::UnitOfWork.new('1',Chore::JsonEncoder.encode(job), consumer)
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

  it 'should timeout a job that runs too long' do
    work = [Chore::UnitOfWork.new(1, Chore::JsonEncoder.encode(timeout_job), consumer)]
    consumer.should_not_receive(:complete)
    Chore.should_receive(:run_hooks_for).with(:on_timeout, anything())
    Chore::Worker.start(work)
  end
end
