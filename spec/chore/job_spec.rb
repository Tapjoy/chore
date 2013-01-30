require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

class TestJob 
  include Chore::Job
end

describe Chore::Job do
  let(:args) { [1,2, { :a => :hash }] }
  let(:config) { { :queue => 'test_queue', :publisher => Chore::Publisher } }

  before(:each) do
    TestJob.configure config
  end

  after(:each) do
    TestJob.configure config
  end

  it 'should have an publish method' do
    TestJob.should respond_to :publish
  end

  it 'should have a perform method' do
    TestJob.should respond_to :perform
  end

  it 'should require a queue when configuring' do
    expect { TestJob.configure(:queue => nil) }.to raise_error(ArgumentError)
  end

  it 'should require a publisher when configuring' do
    expect { TestJob.configure(:publisher => nil) }.to raise_error(ArgumentError)
  end

  it 'should take params via perform' do
    TestJob.any_instance.should_receive(:perform).with(*args)
    TestJob.perform(*args)
  end

  it 'should store class level configuration' do
    TestJob.configure(:queue => 'test_queue')
    TestJob.options[:queue].should == 'test_queue'
  end

  describe(:publish) do 
    it 'should call an instance of the configured publisher' do
      args = [1,2,{:h => 'ash'}]
      TestJob.configure(:publisher => Chore::Publisher)
      Chore::Publisher.any_instance.should_receive(:publish).with({:class => 'TestJob',:args => args}).and_return(true)
      TestJob.publish(*args)
    end
  end
end
