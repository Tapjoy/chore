require 'spec_helper'
require 'securerandom'

describe Chore::DuplicateDetector do
  let(:memcache) { double("memcache") }
  let(:dedupe) { Chore::DuplicateDetector.new(nil,memcache)}
  let(:message) { double('message') }
  let(:timeout) { 2 }
  let(:queue) { (q = double('queue')).stub(:visibility_timeout).and_return(timeout); q }
  let(:id) { SecureRandom.uuid }

  before(:each) do
    message.stub(:id).and_return(id)
    message.stub(:queue).and_return(queue)
  end

  it 'should not return true if the message has not already been seen' do
    memcache.should_receive(:add).and_return(true)
    dedupe.found_duplicate?(message).should_not be_true
  end

  it 'should return true if the message has already been seen' do
    memcache.should_receive(:add).and_raise(Memcached::NotStored.new)
    dedupe.found_duplicate?(message).should be_true
  end

  it 'should return false if given an invalid message' do
    dedupe.found_duplicate?(double()).should be_false
  end

  it "should set the timeout to be the queue's " do
    memcache.should_receive(:add).with(id,"1",timeout)
    dedupe.found_duplicate?(message).should be_false
  end

end
