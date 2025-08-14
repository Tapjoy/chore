require 'spec_helper'

describe Chore::Queues::PubSub do
  include_context 'fake pubsub objects'

  before(:each) do
    allow(Chore::Queues::PubSub).to receive(:pubsub_client).and_return(pubsub_client)
    allow(Chore).to receive(:prefixed_queue_names).and_return([queue_name])
  end

  context "when managing queues" do
    it 'should create topics and subscriptions that are defined in its internal job name list' do
      expect(pubsub_client).to receive(:create_topic).with(queue_name)
      expect(topic).to receive(:create_subscription).with(subscription_name)
      Chore::Queues::PubSub.create_queues!
    end

    it 'should delete topics and subscriptions that are defined in its internal job name list' do
      expect(pubsub_client).to receive(:subscription).with(subscription_name).and_return(subscription)
      expect(pubsub_client).to receive(:topic).with(queue_name).and_return(topic)
      expect(subscription).to receive(:delete)
      expect(topic).to receive(:delete)
      Chore::Queues::PubSub.delete_queues!
    end

    context 'and checking for existing queues' do
      it 'checks for existing topics/subscriptions' do
        expect(described_class).to receive(:existing_queues).and_return([])
        Chore::Queues::PubSub.create_queues!(true)
      end

      it 'raises an error if a topic/subscription does exist' do
        allow(described_class).to receive(:existing_queues).and_return([queue_name])
        expect{Chore::Queues::PubSub.create_queues!(true)}.to raise_error(RuntimeError)
      end

      it 'does not raise an error if a topic/subscription does not exist' do
        allow(described_class).to receive(:existing_queues).and_return([])
        expect{Chore::Queues::PubSub.create_queues!(true)}.not_to raise_error
      end
    end

    context 'when handling subscription already exists error' do
      it 'should continue when subscription already exists' do
        allow(topic).to receive(:create_subscription).and_raise(Google::Cloud::AlreadyExistsError.new('Already exists'))
        expect(Chore.logger).to receive(:info).with("Chore Creating Pub/Sub Topic and Subscription: #{queue_name}")
        expect(Chore.logger).to receive(:info).with("Subscription #{subscription_name} already exists")
        expect { Chore::Queues::PubSub.create_queues! }.not_to raise_error
      end
    end
  end

  describe '.existing_queues' do
    it 'returns queues that exist' do
      allow(topic).to receive(:exists?).and_return(true)
      allow(subscription).to receive(:exists?).and_return(true)
      expect(described_class.existing_queues).to eq([queue_name])
    end

    it 'filters out queues that do not exist' do
      allow(topic).to receive(:exists?).and_return(false)
      allow(subscription).to receive(:exists?).and_return(false)
      expect(described_class.existing_queues).to eq([])
    end

    it 'handles errors gracefully' do
      allow(pubsub_client).to receive(:topic).and_raise(StandardError.new('Connection error'))
      expect(described_class.existing_queues).to eq([])
    end
  end
end 