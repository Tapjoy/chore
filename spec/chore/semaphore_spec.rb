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
    semaphore.stub(:count) { count }
  end

  it "should have an acquire method" do
    semaphore.should respond_to :acquire
  end

  describe "we must block until a lock is acquired" do
    it "should run the block if a lease is available" do
      semaphore.should_receive(:actually_acquire_lease) { true }
      semaphore.acquire do
        sleep(0.1)
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

    describe "but there are no locks available" do
      let(:count) { 1 }

      it "returns nil" do
        lease = semaphore.acquire
        lease.should be_nil
      end
    end
  end
end
