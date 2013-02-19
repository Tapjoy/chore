require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'timeout'

describe Chore::Manager do

  let(:opts) { { :num_workers => 4, :other_opt => 'hi' } }

  it 'should provide defaults' do
    manager = Chore::Manager.new
    Chore::Manager::DEFAULT_OPTIONS.should == manager.config
  end

  it 'should merge in options' do
    manager = Chore::Manager.new(opts)
    opts.each do |k,v|
      manager.config[k].should == v
    end
  end

  it 'should call create an instance of the defined fetcher' do
    fetcher = mock()
    fetcher.should_receive(:new)
    
    manager = Chore::Manager.new(:fetcher => fetcher)
  end

  describe 'running the manager' do
    let(:fetcher) { mock() }
    let(:manager) { Chore::Manager.new(:fetcher => fetcher)}
    let(:work) { Chore::UnitOfWork.new(Chore::JsonEncoder.encode({:class => 'MyClass',:args => []}),mock()) }
    before(:each) do
      fetcher.should_receive(:new).and_return(fetcher)
    end

    it 'should start the fetcher when starting the manager' do
      fetcher.should_receive(:start)
      manager.start
    end

    describe 'assigning messages' do
      it 'should block if no workers are available' do
        Chore::SingleWorkerStrategy.any_instance.should_receive(:assign).and_return(false)
        expect { 
          Timeout::timeout(0.1) do
            manager.assign(work)
          end 
        }.to raise_error(Timeout::Error)
      end
    end
  end

end
