require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::Consumer do
  let(:queue) { "test" }
  let(:options) { {} }
  let(:consumer) { Chore::Consumer.new(queue) }
  let(:message) { "message" }

  it 'should have a consume method' do
    consumer.should respond_to :consume
  end

  it 'should have a reject method' do
    consumer.should respond_to :reject
  end

  it 'should have a complete method' do
    consumer.should respond_to :complete
  end

  it 'should have a class level reset_connection method' do
    Chore::Consumer.should respond_to :reset_connection!
  end

  it 'should have a class level cleanup method' do
    Chore::Consumer.should respond_to :cleanup
  end

  it 'should not have an implemented consume method' do
    expect { consumer.consume }.to raise_error(NotImplementedError)
  end

  it 'should not have an implemented reject method' do
    expect { consumer.reject(message) }.to raise_error(NotImplementedError)
  end

  it 'should not have an implemented complete method' do
    expect { consumer.complete(message) }.to raise_error(NotImplementedError)
  end
end
