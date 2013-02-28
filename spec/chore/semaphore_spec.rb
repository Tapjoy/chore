require 'spec_helper'

describe Chore::Semaphore do

  let(:resource_name) { "sqs" }
  let(:max_leases) { 1 }
  let(:semaphore) { Chore::Semaphore.new(resource_name, max_leases: max_leases ) }
  let(:zk) { double("zk") }
  let(:count) { 0 }

  before(:each) do
    ZK.stub(:new) { zk }
    zk.stub(:mkdir_p)
    zk.stub(:delete)
    semaphore.stub(:count) { count }
    semaphore.stub(:create_lease!) { "0" }
  end

  it "should have an acquire method" do
    semaphore.should respond_to :acquire
  end

  describe "we must block until a lock is acquired" do
    let(:receiver) { double("something") }

    it "should not register a watch if a lease is available" do
      semaphore.should_receive(:actually_acquire_lease) { true }
      zk.should_not_receive(:register) # <-- this is actually what we're testing
      semaphore.acquire do
        sleep(0.1)
      end
    end

    it "should run the block when a lease is available" do
      zk.should_not_receive(:register)
      receiver.should_receive(:a_method)
      semaphore.acquire do
        receiver.a_method
      end
    end


    describe "but there are no locks available" do
      let(:count) { 1 }

      it "should block if no leases are available" do
        zk.should_receive(:register)
        expect { 
          Timeout::timeout(0.3) do
            semaphore.acquire do
              sleep(1)
            end
          end 
        }.to raise_error(Timeout::Error)
      end
    end
  end
  
  describe "we do not need to block on a lock" do

    it "returns a lease when it can acquire a lock" do
      semaphore.stub(:create_lease!) { "0" }
      lease = semaphore.acquire
      lease.should_not be_nil
    end

    describe "and there are no locks available" do
      let(:count) { 1 }

      it "should return nil" do
        lease = semaphore.acquire
        lease.should be_nil
      end
    end
  end
end
