require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

class SimpleJob
  include Chore::Job
  queue_options :name => 'test', :publisher => FakePublisher

  def perform(*args)
    return args
  end
end

describe Chore::Worker do
  let(:consumer) { double('consumer') }
  let(:manager) { double('manager') }

  it 'should start an instance with passed in args' do
    args = { :some => 'val' }
    worker = Chore::Worker.new(args)
    Chore::Worker.should_receive(:new).with(args).and_return(worker)
    Chore::Worker.any_instance.should_receive(:start)
    Chore::Worker.start([],nil,nil,args)
  end

  it 'should use a default encoder' do
    worker = Chore::Worker.new
    worker.options[:encoder].should == Chore::JsonEncoder
  end

  it 'should process jobs in the queue' do
    10.times do |i|
      args = [i,i+1,{'h' => 'ash'}]
      SimpleJob.perform_async(*args)
    end
    SimpleJob.should_receive(:perform).exactly(10).times
    consumer.should_receive(:complete).exactly(10).times
    Chore::Worker.start(FakePublisher.queue,manager,consumer)
  end
end
