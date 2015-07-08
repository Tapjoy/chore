require 'spec_helper'
require 'securerandom'

describe Chore::DuplicateDetector do
  let(:memcache) { double("memcache") }
  let(:dupe_on_cache_failure) { false }
  let(:dedupe_params)  { { :memcached_client => memcache, :dupe_on_cache_failure => dupe_on_cache_failure } }
  let(:dedupe) { Chore::DuplicateDetector.new(dedupe_params)}
  let(:timeout) { 2 }
  let(:queue_url) {"queue://bogus/url"}
  let(:queue) { double('queue', :visibility_timeout=>timeout, :url=>queue_url) }
  let(:id) { SecureRandom.uuid }
  let(:message) { double('message', :id=>id, :queue=>queue) }
  let(:message_data) {{:id=>message.id, :visibility_timeout=>queue.visibility_timeout, :queue=>queue.url}}

  describe "#found_duplicate" do
    it 'should not return true if the message has not already been seen' do
      memcache.should_receive(:add).and_return(true)
      dedupe.found_duplicate?(message_data).should_not be_true
    end

    it 'should return true if the message has already been seen' do
      memcache.should_receive(:add).and_return(false)
      dedupe.found_duplicate?(message_data).should be_true
    end

    it 'should return false if given an invalid message' do
      dedupe.found_duplicate?({}).should be_false
    end

    it "should return false when identity store errors" do
      memcache.should_receive(:add).and_raise("no")
      dedupe.found_duplicate?(message_data).should be_false
    end

    it "should set the timeout to be the queue's " do
      memcache.should_receive(:add).with(id,"1",timeout).and_return(true)
      dedupe.found_duplicate?(message_data).should be_false
    end

    it "should call #visibility_timeout once and only once" do
      queue.should_receive(:visibility_timeout).once
      memcache.should_receive(:add).at_least(3).times.and_return(true)
      3.times { dedupe.found_duplicate?(message_data) }
    end

    context 'when a memecached connection error occurs' do
      context 'and when Chore.config.dedupe_strategy is set to :strict' do
        let(:dupe_on_cache_failure) { true }

        it "returns true" do
          memcache.should_receive(:add).and_raise
          dedupe.found_duplicate?(message_data).should be_true
        end
      end
    end
  end
end
