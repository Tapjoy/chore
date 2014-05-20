require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::Worker do

  class SimpleJob
    include Chore::Job
    queue_options :name => 'test', :publisher => FakePublisher, :max_attempts => 100

    def perform(*args)
      return args
    end
  end

  let(:consumer) { double('consumer', :complete => nil) }
  let(:job_args) { [1,2,'3'] }
  let(:job) { SimpleJob.job_hash(job_args) }

  it 'should use a default encoder' do
    worker = Chore::Worker.new
    worker.options[:encoder].should == Chore::JsonEncoder
  end

  it 'should process a single job' do
    work = Chore::UnitOfWork.new('1', 'test', 60, Chore::JsonEncoder.encode(job), 0, consumer)
    SimpleJob.should_receive(:perform).with(*job_args)
    consumer.should_receive(:complete).with('1')
    w = Chore::Worker.new(work)
    w.start
  end

  it 'should process multiple jobs' do
    work = []
    10.times do |i|
      work << Chore::UnitOfWork.new(i, 'test', 60, Chore::JsonEncoder.encode(job), 0, consumer)
    end
    SimpleJob.should_receive(:perform).exactly(10).times
    consumer.should_receive(:complete).exactly(10).times
    Chore::Worker.start(work)
  end

  describe 'with errors' do
    context 'on parse' do
      let(:job) { "Not-A-Valid-Json-String" }

      it 'should fail cleanly' do
        work = Chore::UnitOfWork.new(2,'test',60,job,0,consumer)
        consumer.should_not_receive(:complete)
        Chore.should_receive(:run_hooks_for).with(:on_failure, job, anything())
        Chore::Worker.start(work)
      end

      context 'more than the maximum allowed times' do
        before(:each) do
          Chore.config.stub(:max_attempts).and_return(10)
        end

        it 'should permanently fail' do
          work = Chore::UnitOfWork.new(2,'test',60,job,9,consumer)
          Chore.should_receive(:run_hooks_for).with(:on_permanent_failure, 'test', job, anything())
          Chore::Worker.start(work)
        end

        it 'should mark the item as completed' do
          work = Chore::UnitOfWork.new(2,'test',60,job,9,consumer)
          consumer.should_receive(:complete).with(2)
          Chore::Worker.start(work)
        end
      end
    end

    context 'on perform' do
      let(:encoded_job) { Chore::JsonEncoder.encode(job) }
      let(:parsed_job) { JSON.parse(encoded_job) }

      before(:each) do
        SimpleJob.stub(:perform).and_raise(ArgumentError)
        SimpleJob.stub(:run_hooks_for).and_return(true)
      end

      it 'should fail cleanly' do
        work = Chore::UnitOfWork.new(2,'test',60,encoded_job,0,consumer)
        consumer.should_not_receive(:complete)
        SimpleJob.should_receive(:run_hooks_for).with(:on_failure, parsed_job, anything())

        Chore::Worker.start(work)
      end

      context 'more than the maximum allowed times' do
        it 'should permanently fail' do
          work = Chore::UnitOfWork.new(2,'test',60,encoded_job,999,consumer)
          SimpleJob.should_receive(:run_hooks_for).with(:on_permanent_failure, 'test', parsed_job, anything())
          Chore::Worker.start(work)
        end

        it 'should mark the item as completed' do
          work = Chore::UnitOfWork.new(2,'test',60,encoded_job,999,consumer)
          consumer.should_receive(:complete).with(2)
          Chore::Worker.start(work)
        end
      end
    end
  end
end
