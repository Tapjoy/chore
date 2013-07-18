require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::Worker do

  class SimpleJob
    include Chore::Job
    queue_options :name => 'test', :publisher => FakePublisher

    def perform(*args)
      return args
    end
  end

  let(:consumer) { double('consumer') }
  let(:job_args) { [1,2,'3'] }
  let(:job) { SimpleJob.job_hash(job_args) }

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
