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
      expect(memcache).to receive(:add).and_return(true)
      expect(dedupe.found_duplicate?(message_data)).to_not be true
    end

    it 'should return true if the message has already been seen' do
      expect(memcache).to receive(:add).and_return(false)
      expect(dedupe.found_duplicate?(message_data)).to be true
    end

    it 'should return false if given an invalid message' do
      expect(dedupe.found_duplicate?({})).to be false
    end

    it "should return false when identity store errors" do
      expect(memcache).to receive(:add).and_raise("no")
      expect(dedupe.found_duplicate?(message_data)).to be false
    end

    it "should set the timeout to be the queue's " do
      expect(memcache).to receive(:add).with(id,"1",timeout).and_return(true)
      expect(dedupe.found_duplicate?(message_data)).to be false
    end

    it "should call #visibility_timeout once and only once" do
      expect(queue).to receive(:visibility_timeout).once
      expect(memcache).to receive(:add).at_least(3).times.and_return(true)
      3.times { dedupe.found_duplicate?(message_data) }
    end

    context 'when a memecached connection error occurs' do
      context 'and when Chore.config.dedupe_strategy is set to :strict' do
        let(:dupe_on_cache_failure) { true }

        it "returns true" do
          expect(memcache).to receive(:add).and_raise
          expect(dedupe.found_duplicate?(message_data)).to be true
        end
      end
    end
  end
end
