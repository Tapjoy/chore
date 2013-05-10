require 'spec_helper'

module Chore
  describe Queues::SQS::Publisher do
    let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']}}
    let(:queue_name) { 'test_queue' }
    let(:queue) { double('queue') }
    let(:publisher) { Queues::SQS::Publisher.new }

    before(:each) do
      AWS::SQS.stub(:new)
      publisher.should_receive(:ensure_queue!).with(queue_name).and_return(queue)
    end

    it 'should create send an encoded message to the specified queue' do
      queue.should_receive(:send_message).with(job.to_json)
      publisher.publish(queue_name,job)
    end
  end
end
