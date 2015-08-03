require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::Worker do

  class SimpleJob
    include Chore::Job
    queue_options :name => 'test',
      :publisher => FakePublisher,
      :max_attempts => 100

    def perform(*args)
      return args
    end
  end

  let(:consumer) { double('consumer', :complete => nil) }
  let(:job_args) { [1,2,'3'] }
  let(:job) { SimpleJob.job_hash(job_args) }

  it 'should use a default payload handler' do
    worker = Chore::Worker.new
    worker.options[:payload_handler].should == Chore::Job
  end

  shared_examples_for "a worker" do
    it 'processing a single job' do
      work = Chore::UnitOfWork.new('1', 'test', 60, encoded_job, 0, consumer)
      SimpleJob.should_receive(:perform).with(*payload)
      consumer.should_receive(:complete).with('1')
      w = Chore::Worker.new(work, {:payload_handler => payload_handler})
      w.start
    end

    it 'processing multiple jobs' do
      work = []
      10.times do |i|
        work << Chore::UnitOfWork.new(i, 'test', 60, encoded_job, 0, consumer)
      end
      SimpleJob.should_receive(:perform).exactly(10).times
      consumer.should_receive(:complete).exactly(10).times
      Chore::Worker.start(work, {:payload_handler => payload_handler})
    end
  end

  describe "with default payload handler" do
    let(:encoded_job) { Chore::Encoder::JsonEncoder.encode(job) }
    let(:payload_handler) { Chore::Job }
    let(:payload) {job_args}
    it_behaves_like "a worker"
  end

  describe 'expired?' do
    let(:now) { Time.now }
    let(:queue_timeouts) { [10, 20, 30] }
    let(:work) do
      queue_timeouts.map do |queue_timeout|
        Chore::UnitOfWork.new('1', 'test', queue_timeout, Chore::Encoder::JsonEncoder.encode(job), 0, consumer)
      end
    end
    let(:worker) do
      Timecop.freeze(now) do
        Chore::Worker.new(work)
      end
    end

    it 'should not be expired when before total timeout' do
      worker.should_not be_expired
    end

    it 'should not be expired when at total timeout' do
      Timecop.freeze(now + 60) do
        worker.should_not be_expired
      end
    end

    it 'should be expired when past total timeout' do
      Timecop.freeze(now + 61) do
        worker.should be_expired
      end
    end
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
      let(:encoded_job) { Chore::Encoder::JsonEncoder.encode(job) }
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

  describe 'delaying retries' do
    let(:encoded_job) { Chore::Encoder::JsonEncoder.encode(job) }
    let(:parsed_job) { JSON.parse(encoded_job) }
    let(:work) { Chore::UnitOfWork.new(2, 'test', 60, encoded_job, 0, consumer) }

    before(:each) do
      SimpleJob.options[:backoff] = lambda { |work| work.current_attempt }

      allow(SimpleJob).to receive(:perform).and_raise(RuntimeError)
      SimpleJob.stub(:run_hooks_for).and_return(true)
    end

    context 'and the consumer can delay' do
      before(:each) do
        allow(consumer).to receive(:delay).and_return(0)
      end

      it 'will not complete the message' do
        expect(consumer).not_to receive(:complete)
        Chore::Worker.start(work)
      end

      it 'will delay the message' do
        expect(consumer).to receive(:delay).with(work, SimpleJob.options[:backoff])
        Chore::Worker.start(work)
      end

      it 'triggers the on_delay callback' do
        expect(SimpleJob).to receive(:run_hooks_for).with(:on_delay, parsed_job)
        Chore::Worker.start(work)
      end
    end

    context 'and the consumer cannot delay' do
      before(:each) do
        allow(consumer).to receive(:delay).and_raise(NoMethodError)
      end

      it 'will not complete the item' do
        expect(consumer).not_to receive(:complete)
        Chore::Worker.start(work)
      end

      it 'triggers the failure callback' do
        worker = Chore::Worker.new(work)
        expect(worker).to receive(:handle_failure)
        worker.start
      end
    end
  end
end
