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
    Chore::Worker.start(args)
  end

  describe('FakeWorker') do
    it 'should process jobs in the queue' do
      args = [1,2,{'h' => 'ash'}]
      SimpleJob.publish(*args)
      SimpleJob.any_instance.should_receive(:perform).with(*args)
      FakeWorker.start
    end
  end
end
