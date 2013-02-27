require 'spec_helper'

describe Chore::Semaphore do

  let(:resource_name) { "sqs" }
  let(:max_locks) { 1 }
  let(:semaphore) { Chore::Semaphore.new(resource_name, max_locks: max_locks ) }
  let(:zk) { double("zk") }

  before do
    ZK.stub(:new) { zk }
    zk.stub(:mkdir_p)
  end

  it "should have an acquire method" do
    semaphore.should respond_to :acquire
  end

end
