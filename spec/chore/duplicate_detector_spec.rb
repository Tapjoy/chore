require 'spec_helper'
require 'securerandom'

describe Chore::DuplicateDetector do
  let(:memcache) { double("memcache") }
  let(:dupe_on_cache_failure) { false }
  let(:dedupe_params)  { { :memcached_client => memcache, :dupe_on_cache_failure => dupe_on_cache_failure } }
  let(:dedupe) { Chore::DuplicateDetector.new(dedupe_params)}
  let(:message) { double('message') }
  let(:timeout) { 2 }
  let(:queue_url) {"queue://bogus/url"}
  let(:queue) { (q = double('queue')).stub(:visibility_timeout).and_return(timeout); q.stub(:url).and_return(queue_url); q }
  let(:id) { SecureRandom.uuid }

  before(:each) do
    message.stub(:id).and_return(id)
    message.stub(:queue).and_return(queue)
  end

  describe "#found_duplicate" do
    it 'should not return true if the message has not already been seen' do
      memcache.should_receive(:add).and_return(true)
      dedupe.found_duplicate?(message).should_not be_true
    end

    it 'should return true if the message has already been seen' do
      memcache.should_receive(:add).and_return(false)
      dedupe.found_duplicate?(message).should be_true
    end

    it 'should return false if given an invalid message' do
      dedupe.found_duplicate?(double()).should be_false
    end

    it "should return false when identity store errors" do
      memcache.should_receive(:add).and_raise("no")
      dedupe.found_duplicate?(message).should be_false
    end

    it "should set the timeout to be the queue's " do
      memcache.should_receive(:add).with(id,"1",timeout).and_return(true)
      dedupe.found_duplicate?(message).should be_false
    end

    it "should call #visibility_timeout once and only once" do
      queue.should_receive(:visibility_timeout).once
      memcache.should_receive(:add).at_least(3).times.and_return(true)
      3.times { dedupe.found_duplicate?(message) }
    end

    context 'when a memecached connection error occurs' do
      context 'and when Chore.config.dedupe_strategy is set to :strict' do
        let(:dupe_on_cache_failure) { true }

        it "returns true" do
          memcache.should_receive(:add).and_raise
          dedupe.found_duplicate?(message).should be_true
        end
      end
    end
  end
end
