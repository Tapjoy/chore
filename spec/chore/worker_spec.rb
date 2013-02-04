require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

class SimpleJob
  include Chore::Job
  configure :queue => 'test', :publisher => FakePublisher

  def perform(*args)
    return args
  end
end

describe Chore::Worker do
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

  describe('FakeWorker') do
    it 'should process jobs in the queue' do
      10.times do |i|
        args = [i,i+1,{'h' => 'ash'}]
        SimpleJob.publish(*args)
      end
      SimpleJob.should_receive(:perform).exactly(10).times
      FakeWorker.start(FakePublisher.queue)
    end
  end
end
