require 'spec_helper'

describe Chore::Queues::SQS::Publisher do
  include_context 'fake objects'

  let(:publisher) { Chore::Queues::SQS::Publisher.new }
  let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']}}
  let(:send_message_result) { double(Aws::SQS::Types::SendMessageResult, :data => job) }

  before(:each) do
    allow(Aws::SQS::Client).to receive(:new).and_return(sqs)
    allow(sqs).to receive(:send_message).and_return(send_message_result)
  end

  it 'should configure sqs' do
    expect(Aws::SQS::Client).to receive(:new)
    publisher.publish(queue_name,job)
  end

  it 'should not create a new SQS client before every publish' do
    expect(Aws::SQS::Client).to receive(:new).once
    2.times { publisher.send(:queue, queue_name) }
  end

  it 'should lookup the queue when publishing' do
    expect(sqs).to receive(:get_queue_url).with(queue_name: queue_name)
    publisher.publish(queue_name, job)
  end

  it 'should create send an encoded message to the specified queue' do
    expect(sqs).to receive(:send_message).with({queue_url: queue_url, message_body: job.to_json})
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
    4.times { publisher.publish(queue_name, job) }
  end

  describe '#reset_connection!' do
    it 'should empty API client connection pool after a call to reset_connection!' do
      expect(Aws).to receive(:empty_connection_pools!)
      Chore::Queues::SQS::Publisher.reset_connection!
      publisher.send(:queue, queue_name)
    end

    # TODO: this test seems like basic identity (i.e. not even a real test)
    it 'should not reset the connection between calls' do
      expect(Aws).to receive(:empty_connection_pools!).once
      Chore::Queues::SQS::Publisher.reset_connection!
      4.times { publisher.send(:queue, queue_name ) }
    end
  end
end
