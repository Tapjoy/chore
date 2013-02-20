require 'spec_helper'

describe Chore::Job do
  let(:args) { [1,2, { :a => :hash }] }
  let(:config) { { :name => 'test_queue', :publisher => Chore::Publisher } }

  before(:each) do
    TestJob.queue_options config
  end

  after(:each) do
    TestJob.queue_options config
  end

  it 'should have an perform_async method' do
    TestJob.should respond_to :perform_async
  end

  it 'should have a perform method' do
    TestJob.should respond_to :perform
  end

  it 'should require a queue when configuring' do
    expect { TestJob.queue_options(:name => nil) }.to raise_error(ArgumentError)
  end

  it 'should require a publisher when configuring' do
    expect { TestJob.queue_options(:publisher => nil) }.to raise_error(ArgumentError)
  end

  it 'should take params via perform' do
    TestJob.any_instance.should_receive(:perform).with(*args)
    TestJob.perform(*args)
  end

  it 'should store class level configuration' do
    TestJob.queue_options(:name => 'test_queue')
    TestJob.options[:name].should == 'test_queue'
  end

  describe(:perform_async) do 
    it 'should call an instance of the queue_optionsd publisher' do
      args = [1,2,{:h => 'ash'}]
      TestJob.queue_options(:publisher => Chore::Publisher)
      Chore::Publisher.any_instance.should_receive(:publish).with({:class => 'TestJob',:args => args}).and_return(true)
      TestJob.perform_async(*args)
    end
  end
end
