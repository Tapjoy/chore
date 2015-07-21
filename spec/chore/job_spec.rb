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
    it 'should call an instance of the queue_options publisher' do
      args = [1,2,{:h => 'ash'}]
      TestJob.queue_options(:publisher => Chore::Publisher)
      Chore::Publisher.any_instance.should_receive(:publish).with(
        'test_queue',
        {:class => 'TestJob', :args => args},
        {}).and_return(true)
      TestJob.perform_async(*args)
    end
  end

  describe 'publisher configured via Chore.configure' do
    before do
      Chore.configure do |c|
        c.publisher = Chore::Publisher
      end

      class NoPublisherJob
        include Chore::Job
        queue_options :name => "test_queue"

        def perform
        end
      end
    end

    it 'should have the default publisher' do
      NoPublisherJob.options[:publisher].should == Chore::Publisher
    end

    describe 'global publisher can be overridden' do
      before do
        TestJob.queue_options config.merge(:publisher => FakePublisher)
      end

      it 'should override publisher' do
        TestJob.options[:publisher].should == FakePublisher
        TestJob.options[:publisher].should_not == Chore::Publisher
      end
    end
  end
end
