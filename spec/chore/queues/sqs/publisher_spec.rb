require 'spec_helper'

module Chore
  describe Queues::SQS::Publisher do
    let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']}}
    let(:queue_name) { 'test_queue' }
    let(:queue) { double('queue', :send_message => nil) }
    let(:sqs) do
      double('sqs', :queues => double('queues', :named => queue))
    end
    let(:publisher) { Queues::SQS::Publisher.new }

    before(:each) do
      AWS::SQS.stub(:new).and_return(sqs)
    end

    it 'should create send an encoded message to the specified queue' do
      queue.should_receive(:send_message).with(job.to_json)
      publisher.publish(queue_name,job)
    end

    it 'should lookup the queue when publishing' do
      sqs.queues.should_receive(:named).with('test_queue')
      publisher.publish('test_queue', job)
    end

    it 'should lookup multiple queues if specified' do
      sqs.queues.should_receive(:named).with('test_queue')
      sqs.queues.should_receive(:named).with('test_queue2')
      publisher.publish('test_queue', job)
      publisher.publish('test_queue2', job)
    end

    it 'should only lookup a named queue once' do
      sqs.queues.should_receive(:named).with('test_queue').once
      2.times { publisher.publish('test_queue', job) }
    end
  end
end
