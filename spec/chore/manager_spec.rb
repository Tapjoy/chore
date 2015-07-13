require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'timeout'

describe Chore::Manager do

  let(:fetcher) { double(:start => nil) }
  let(:opts) { { :num_workers => 4, :other_opt => 'hi', :fetcher => fetcher } }

  before(:each) do
    Chore.configure {|c| c.fetcher = fetcher; c.worker_strategy = Chore::Strategy::SingleWorkerStrategy }
    expect(fetcher).to receive(:new).and_return(fetcher)
  end

  describe 'running the manager' do

    let(:manager) { Chore::Manager.new }
    let(:work) do
      Chore::UnitOfWork.new(Chore::Encoder::JsonEncoder.encode({ :class => 'MyClass', :args => [] }), double())
    end

    it 'should start the fetcher when starting the manager' do
      expect(fetcher).to receive(:start)
      manager.start
    end

    describe 'assigning messages' do
      let(:worker) { double() }

      before(:each) do
        expect(worker).to receive(:start).with no_args
      end

      it 'should create a worker if one is available' do
        expect(Chore::Worker).to receive(:new).with(work,{}).and_return(worker)
        manager.assign(work)
      end
    end
  end

end
