require 'spec_helper'

module Chore
  describe Queues::SQS::Publisher do
    let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']}}
    let(:queue_name) { 'test_queue' }
    let(:queue_url) {"http://www.queue_url.com/test_queue"}
    let(:message_result) { double(Aws::SQS::Types::SendMessageResult, :data => job) }
    let(:queue) { double(Aws::SQS::Queue, :send_message => sqs.send_message) }
    let(:sqs) do
      double(Aws::SQS::Client,
        :get_queue_url => double(Aws::SQS::Types::GetQueueUrlResult, :queue_url => queue_url),
        :send_message => message_result,
      )
    end
    let(:publisher) { Queues::SQS::Publisher.new }

    before(:each) do
      allow(Aws::SQS::Client).to receive(:new).and_return(sqs)
    end

    it 'should configure sqs' do
      expect(Aws::SQS::Client).to receive(:new)
      publisher.publish(queue_name,job)
    end

    it 'should create a new SQS client before every publish' do
      # Chore::Queues::SQS::Publisher.reset_connection!
      expect(Aws::SQS::Client).to receive(:new).twice
      publisher.send(:queue, queue_name)
      publisher.send(:queue, queue_name)
    end

    it 'should lookup the queue when publishing' do
      expect(sqs).to receive(:get_queue_url).with(queue_name: queue_name)
      publisher.publish(queue_name, job)
    end

    it 'should create send an encoded message to the specified queue' do
      expect(sqs).to receive(:send_message).with(queue_url: queue_url, message_body: job.to_json)
      publisher.publish(queue_name,job)
    end

    it 'should lookup multiple queues if specified' do
      second_queue_name = queue_name + '2'
      expect(sqs).to receive(:get_queue_url).with(queue_name: queue_name)
      expect(sqs).to receive(:get_queue_url).with(queue_name: second_queue_name)

      publisher.publish(queue_name, job)
      publisher.publish(second_queue_name, job)
    end

    it 'should only lookup a named queue once' do
      expect(sqs).to receive(:get_queue_url).with(queue_name: queue_name).once
      4.times { publisher.publish('test_queue', job) }
    end

    describe '#reset_connection!' do
      it 'should empty API client connection pool after a call to reset_connection!' do
        expect(Aws).to receive(:empty_connection_pools!)
        Chore::Queues::SQS::Publisher.reset_connection!
      end

      # TODO: the reset_connection! method is setup so every call resets it, so this spec shouldn't even exist right?
      xit 'should not reset the connection between calls' do
        sqs = publisher.send(:queue, queue_name)
        expect(sqs).to be publisher.send(:queue, queue_name) # TODO: this seems like basic identity (i.e. not even a real test)
      end
    end
  end
end
