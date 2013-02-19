require 'spec_helper'

class TestConsumer < Chore::Consumer
  def initialize(queue_name, opts={})
  end

  def consume
    yield "test" if block_given?
  end
end

describe Chore::Fetcher do

  let(:manager) { Chore::Manager.new }
  let(:consumer) { TestConsumer }
  let(:fetcher) { Chore::Fetcher.new(manager, :consumer => consumer, :queue_name => "test") }

  it "should have a fetch function" do
    fetcher.should respond_to :fetch
  end

  describe "fetching messages" do
    it "should receive a message from the queue" do
      consumer.any_instance.should_receive(:consume)
      fetcher.fetch
    end

    it "should assign its message" do
      manager.should_receive(:assign)
      fetcher.fetch
    end
  end
end
