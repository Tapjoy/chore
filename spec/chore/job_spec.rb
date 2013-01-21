require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

class TestJob < Chore::Job
  configure :queue => 'test_queue'
end

describe Chore::Job do
  let(:args) { [1,2, { :a => :hash }] }

  it 'should have an publish method' do
    subject.class.should respond_to :publish
  end

  it 'should have a perform method' do
    subject.class.should respond_to :perform
  end

  it 'should use a default encoder' do
    TestJob.options[:encoder].should == Chore::JsonEncoder
  end

  it 'should require a queue when configuring' do
    expect { TestJob.configure(:queue => nil) }.to raise_error(ArgumentError)
  end

  it 'should take params via perform' do
    job = TestJob.new
    TestJob.should_receive(:new).with(*args).and_return(job)
    TestJob.any_instance.should_receive(:perform)
    TestJob.perform(*args)
  end

  it 'should store class level configuration' do
    TestJob.configure(:queue => 'test_queue')
    TestJob.options[:queue].should == 'test_queue'
  end

  describe 'instances' do
    it 'should set params via initialize' do
      TestJob.new(*args).params.should == args
    end

  end
end
