require 'spec_helper'

class TestConsumer < Chore::Consumer
  def initialize(queue_name, opts={})
  end

  def consume
    # just something that looks like an SQS message
    msg = OpenStruct.new( :id => 1, :body => "test" )
    yield msg if block_given?
  end
end

describe Chore::Fetcher do
  let(:manager) { double("manager") }
  let(:consumer) { TestConsumer }
  let(:fetcher) { Chore::Fetcher.new(manager) }

  before(:each) do
    Chore.configure do |c| 
      c.queues = ['test'] 
      c.consumer = consumer
      c.batch_size = 1
    end
  end


  it "should have a start function" do
    fetcher.should respond_to :start
  end

  describe "fetching messages" do
    it "should assign its message" do
      manager.should_receive(:assign)
      fetcher.start
    end
  end

  describe "cleaning up" do
    before(:each) do
      manager.stub(:assign)
    end
    
    it "should run cleanup on each queue" do
      consumer.should_receive(:cleanup).with('test')
      fetcher.start
    end
  end
end
