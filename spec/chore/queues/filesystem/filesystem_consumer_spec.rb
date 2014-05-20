require 'spec_helper'

# This test is actually testing both the publisher and the consumer behavior but what we
# really want to validate is that they can pass messages off to each other. Hard coding in
# the behavior of each in two separate tests was becoming a mess and would be hard to maintain.
describe Chore::Queues::Filesystem::Consumer do
  let(:consumer) { Chore::Queues::Filesystem::Consumer.new(test_queue) }
  let(:publisher) { Chore::Queues::Filesystem::Publisher.new }
  let(:test_queues_dir) { "test-queues" }
  let(:test_queue) { "test-queue" }

  before do
    Chore.config.fs_queue_root = test_queues_dir
    consumer.stub(:sleep)
  end
  
  after do
    FileUtils.rm_rf(test_queues_dir)
  end
  
  let!(:consumer_run_for_one_message) { consumer.stub(:running?).and_return(true, false) }
  let(:test_job_hash) {{:class => "TestClass", :args => "test-args"}}

  context "founding a published job" do
    before do
      publisher.publish(test_queue, test_job_hash)
    end

    it "should consume a published job and yield the job to the handler block" do
      expect { |b| consumer.consume(&b) }.to yield_with_args(anything, 'test-queue', nil, test_job_hash.to_json, 0)
    end

    context "rejecting a job" do
      let!(:consumer_run_for_two_messages) { consumer.stub(:running?).and_return(true, false,true,false) }
    
      it "should requeue a job that gets rejected" do
        rejected = false
        consumer.consume do |job_id, queue_name, job_hash|
          consumer.reject(job_id)
          rejected = true
        end
        rejected.should be_true

        expect { |b| consumer.consume(&b) }.to yield_with_args(anything, 'test-queue', nil, test_job_hash.to_json, 1)
      end
    end
    
    context "completing a job" do
      let!(:consumer_run_for_two_messages) { consumer.stub(:running?).and_return(true, false,true,false) }
    
      it "should remove job on completion" do
        completed = false
        consumer.consume do |job_id, queue_name, job_hash|
          consumer.complete(job_id)
          completed = true
        end
        completed.should be_true

        expect { |b| consumer.consume(&b) }.to_not yield_control
      end
    end
  end

  context "not finding a published job" do
    it "should consume a published job and yield the job to the handler block" do
      expect { |b| consumer.consume(&b) }.to_not yield_control
    end
  end
end

