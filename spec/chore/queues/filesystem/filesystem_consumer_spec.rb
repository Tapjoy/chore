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
    expect(Chore.config).to receive(:default_queue_timeout).and_return(60)
    allow(consumer).to receive(:sleep)
  end

  after do
    FileUtils.rm_rf(test_queues_dir)
  end

  let(:test_job_hash) {{:class => "TestClass", :args => "test-args"}}
  let(:new_dir) { described_class.new_dir(test_queue) }
  let(:in_progress_dir) { described_class.in_progress_dir(test_queue) }

  describe ".cleanup" do
    it "should move in_progress jobs to new dir" do
      FileUtils.touch("#{in_progress_dir}/foo.1.job")
      described_class.cleanup(test_queue)
      expect(File.exist?("#{new_dir}/foo.2.job")).to eq(true)
    end
  end

  describe ".make_in_progress" do
    it "should move job to in_progress dir" do
      FileUtils.touch("#{new_dir}/foo.1.job")
      described_class.make_in_progress("foo.1.job", new_dir, in_progress_dir)
      expect(File.exist?("#{in_progress_dir}/foo.1.job")).to eq(true)
    end
  end

  describe ".make_new_again" do
    it "should move job to new dir" do
      FileUtils.touch("#{in_progress_dir}/foo.1.job")
      described_class.make_new_again("foo.1.job", new_dir, in_progress_dir)
      expect(File.exist?("#{new_dir}/foo.2.job")).to eq(true)
    end
  end

  describe ".each_file" do
    it "should list jobs in dir" do
      FileUtils.touch("#{new_dir}/foo.1.job")
      expect {|b| described_class.each_file("#{new_dir}/*.job", &b) }.to yield_with_args("foo.1.job")
    end
  end

  describe ".file_info" do
    it "should split name and attempt number" do
      name, attempt = described_class.file_info("foo.1.job")
      expect(name).to eq("foo")
      expect(attempt).to eq(1)
    end
  end

  describe 'consumption' do
    let!(:consumer_run_for_one_message) { expect(consumer).to receive(:running?).and_return(true, false) }

    context "founding a published job" do
      before do
        publisher.publish(test_queue, test_job_hash)
      end

      it "should consume a published job and yield the job to the handler block" do
        expect { |b| consumer.consume(&b) }.to yield_with_args(anything, 'test-queue', 60, test_job_hash.to_json, 0)
      end

      context "rejecting a job" do
        let!(:consumer_run_for_two_messages) { allow(consumer).to receive(:running?).and_return(true, false,true,false) }

        it "should requeue a job that gets rejected" do
          rejected = false
          consumer.consume do |job_id, queue_name, job_hash|
            consumer.reject(job_id)
            rejected = true
          end
          expect(rejected).to be true

          expect { |b| consumer.consume(&b) }.to yield_with_args(anything, 'test-queue', 60, test_job_hash.to_json, 1)
        end
      end

      context "completing a job" do
        let!(:consumer_run_for_two_messages) { allow(consumer).to receive(:running?).and_return(true, false,true,false) }

        it "should remove job on completion" do
          completed = false
          consumer.consume do |job_id, queue_name, job_hash|
            consumer.complete(job_id)
            completed = true
          end
          expect(completed).to be true

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
end

