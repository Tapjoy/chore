require 'spec_helper'

describe Chore::Queues::PubSub::Publisher do
  include_context 'fake pubsub objects'

  let(:publisher) { Chore::Queues::PubSub::Publisher.new }
  let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']} }
  let(:publish_result) { double('Google::Cloud::PubSub::Message', message_id: message_id) }

  before(:each) do
    allow(Chore::Queues::PubSub).to receive(:pubsub_client).and_return(pubsub_client)
    allow(topic).to receive(:publish).and_return(publish_result)
  end

  it 'should configure pubsub client' do
    expect(Chore::Queues::PubSub).to receive(:pubsub_client)
    publisher.publish(queue_name, job)
  end

  it 'should not create a new Pub/Sub client before every publish' do
    expect(Chore::Queues::PubSub).to receive(:pubsub_client).once
    2.times { publisher.send(:get_topic, queue_name) }
  end

  it 'should lookup the topic when publishing' do
    expect(pubsub_client).to receive(:publisher).with(queue_name).and_return(topic)
    publisher.publish(queue_name, job)
  end

  it 'should publish an encoded message to the specified topic' do
    expect(topic).to receive(:publish).with(job.to_json)
    publisher.publish(queue_name, job)
  end

  it 'should lookup multiple topics if specified' do
    second_queue_name = queue_name + '2'
    second_topic = double('Google::Cloud::PubSub::Topic')
    
    expect(pubsub_client).to receive(:publisher).with(queue_name).and_return(topic)
    expect(pubsub_client).to receive(:publisher).with(second_queue_name).and_return(second_topic)
    expect(topic).to receive(:publish)
    expect(second_topic).to receive(:publish)

    publisher.publish(queue_name, job)
    publisher.publish(second_queue_name, job)
  end

  it 'should only lookup a named topic once' do
    expect(pubsub_client).to receive(:publisher).with(queue_name).once.and_return(topic)
    expect(topic).to receive(:publish).exactly(4).times
    4.times { publisher.publish(queue_name, job) }
  end

  describe '#reset_connection!' do
    it 'should reset client connection after a call to reset_connection!' do
      # First call establishes the client
      publisher.send(:get_topic, queue_name)
      
      # Reset and verify client is reset
      Chore::Queues::PubSub::Publisher.reset_connection!
      
      expect(Chore::Queues::PubSub).to receive(:pubsub_client).and_return(pubsub_client)
      publisher.send(:get_topic, queue_name)
    end

    it 'should clear topic cache after reset_connection!' do
      # Establish topic cache
      publisher.send(:get_topic, queue_name)
      
      # Reset connection
      Chore::Queues::PubSub::Publisher.reset_connection!
      
      # Should lookup topic again
      expect(pubsub_client).to receive(:publisher).with(queue_name).and_return(topic)
      publisher.send(:get_topic, queue_name)
    end

    it 'should not reset the connection between calls' do
      expect(Chore::Queues::PubSub).to receive(:pubsub_client).once.and_return(pubsub_client)
      Chore::Queues::PubSub::Publisher.reset_connection!
      4.times { publisher.send(:get_topic, queue_name) }
    end
  end

  describe 'encoding' do
    it 'should encode job to JSON' do
      encoded_job = publisher.send(:encode_job, job)
      expect(encoded_job).to eq(job.to_json)
    end
  end
end 