require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::Consumer do
  let(:queue) { "test" }
  let(:options) { {} }
  let(:consumer) { Chore::Consumer.new(queue) }
  let(:message) { "message" }

  it 'should have a consume method' do
    expect(consumer).to respond_to :consume
  end

  it 'should have a reject method' do
    expect(consumer).to respond_to :reject
  end

  it 'should have a complete method' do
    expect(consumer).to respond_to :complete
  end

  it 'should have a class level reset_connection method' do
    expect(Chore::Consumer).to respond_to :reset_connection!
  end

  it 'should not have an implemented consume method' do
    expect { consumer.consume }.to raise_error(NotImplementedError)
  end

  it 'should not have an implemented reject method' do
    expect { consumer.reject(message) }.to raise_error(NotImplementedError)
  end

  it 'should not have an implemented complete method' do
    expect { consumer.complete(message, nil) }.to raise_error(NotImplementedError)
  end

  it 'should have a dupe detector' do
    expect(consumer.dupe_detector).not_to be_nil
  end

  it 'should not provide a handler to the dupe detector' do
    expect(Chore::DuplicateDetector).to receive(:new).with({:dupe_on_cache_failure => false})
    consumer.dupe_detector
  end
end
