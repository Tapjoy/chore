require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'timeout'

describe Chore::Manager do

  let(:fetcher) { mock(:start => nil) }
  let(:opts) { { :num_workers => 4, :other_opt => 'hi', :fetcher => fetcher } }

  before(:each) do
    Chore.configure {|c| c.fetcher = fetcher; c.worker_strategy = Chore::Strategy::SingleWorkerStrategy }
    fetcher.should_receive(:new).and_return(fetcher)
  end

  it 'should call create an instance of the defined fetcher' do
    manager = Chore::Manager.new
  end

  

  describe 'running the manager' do

    let(:manager) { Chore::Manager.new}
    let(:work) { Chore::UnitOfWork.new(Chore::Encoder::JsonEncoder.encode({:class => 'MyClass',:args => []}),mock()) }

    it 'should start the fetcher when starting the manager' do
      fetcher.should_receive(:start)
      manager.start
    end

    describe 'assigning messages' do
      let(:worker) { mock() }

      before(:each) do
        worker.should_receive(:start).with()
      end

      it 'should create a worker if one is available' do
        Chore::Worker.should_receive(:new).with(work,{}).and_return(worker)
        manager.assign(work)
      end
    end
  end

end
