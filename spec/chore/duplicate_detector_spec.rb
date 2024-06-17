require 'spec_helper'
require 'securerandom'

describe Chore::DuplicateDetector do
  class FakeDalli
    def initialize
      @store = {}
    end
    def add(id, val, ttl=0)
      if @store[id] && @store[id][:inserted] + @store[id][:ttl] > Time.now.to_i
        return false
      else
        @store[id] = {:val => val, :ttl => ttl, :inserted => Time.now.to_i}
        return true
      end
    end
  end

  let(:memcache) { FakeDalli.new }
  let(:handler) { memcache.method(:add) }
  let(:dupe_on_cache_failure) { false }
  let(:dedupe_params)  { { :handler => handler, :dupe_on_cache_failure => dupe_on_cache_failure } }
  let(:dedupe) { Chore::DuplicateDetector.new(dedupe_params)}
  let(:timeout) { 20 }
  let(:timeout_offset) { 10 }
  let(:queue_url) {"queue://bogus/url"}
  let(:queue) { double('queue', :visibility_timeout=>timeout, :url=>queue_url) }
  let(:id) { SecureRandom.uuid }
  let(:message) { double('message', :id=>id, :queue=>queue) }
  let(:message_data) {{:id=>message.id, :visibility_timeout=>queue.visibility_timeout, :queue=>queue.url, :received_timestamp=>Time.utc(2024, 5, 10, 12, 0, 0)}}

  describe "#found_duplicate" do
    it 'should not return true if the message has not already been seen' do
      expect(dedupe.found_duplicate?(message_data)).to_not be true
    end

    it 'should return true if the message has already been seen' do
      memcache.add(message_data[:id], 1, message_data[:visibility_timeout])
      expect(dedupe.found_duplicate?(message_data)).to be true
    end

    it 'should return false if given an invalid message' do
      expect(dedupe.found_duplicate?({})).to be false
    end

    it "should return false when identity store errors" do
      expect(memcache).to receive(:add).and_raise("no")
      expect(dedupe.found_duplicate?(message_data)).to be false
    end

    it "should set the timeout to be queue timeout with offset" do
      allow(Time).to receive(:now).and_return(Time.utc(2024, 5, 10, 12, 0, 0))
      expect(memcache).to receive(:add).with(id,"1",10).and_call_original
      expect(dedupe.found_duplicate?(message_data)).to be false
    end

    it "should call #visibility_timeout once and only once" do
      expect(queue).to receive(:visibility_timeout).once
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

  describe "#get_received_timestamp_offset" do
    context 'when received_timestamp is 10 seconds before it is worked on' do
      it "should return a 10 second offset" do
        # Set received_timestamp_offset to 10 second offset
        allow(Time).to receive(:now).and_return(Time.utc(2024, 5, 10, 12, 0, 10))

        expect(dedupe.get_received_timestamp_offset(message_data[:received_timestamp])).to eq(10)
      end
    end
  end
end
