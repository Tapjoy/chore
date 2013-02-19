require 'spec_helper'

class TestConsumer < Chore::Consumer
  def initialize(queue_name, opts={})
  end

  def consume
    msg = OpenStruct.new( :id => 1, :body => "test" )
    yield msg if block_given?
  end
end

describe Chore::Fetcher do

  let(:manager) { double("manager") }
  let(:consumer) { TestConsumer }
  let(:fetcher) { Chore::Fetcher.new(manager, :consumers => [{:class => consumer, :queue => "test"}]) }

  it "should have a start function" do
    fetcher.should respond_to :start
  end

  describe "fetching messages" do
    it "should assign its message" do
      manager.should_receive(:assign)
      fetcher.start
    end
  end
end
