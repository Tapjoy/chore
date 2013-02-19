require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'timeout'

describe Chore::Manager do

  let(:fetcher) { mock() }
  let(:opts) { { :num_workers => 4, :other_opt => 'hi', :fetcher => fetcher } }

  before(:each) do
    Chore.configure {|c| c.fetcher = fetcher }
    fetcher.should_receive(:new).and_return(fetcher)
  end

  it 'should call create an instance of the defined fetcher' do
    manager = Chore::Manager.new
  end

  describe 'running the manager' do

    let(:manager) { Chore::Manager.new}
    let(:work) { Chore::UnitOfWork.new(Chore::JsonEncoder.encode({:class => 'MyClass',:args => []}),mock()) }

    it 'should start the fetcher when starting the manager' do
      fetcher.should_receive(:start)
      manager.start
    end

    describe 'assigning messages' do
      it 'should block if no workers are available' do
        Chore::SingleWorkerStrategy.any_instance.should_receive(:assign).at_least(:once).and_return(false)
        expect { 
          Timeout::timeout(0.3) do
            manager.assign(work)
          end 
        }.to raise_error(Timeout::Error)
      end

      it 'should create a worker if one is available' do
        worker = mock()
        Chore::Worker.should_receive(:new).and_return(worker)
        worker.should_receive(:start).with(work)
        manager.assign(work)
      end
    end

  end

end
