require 'spec_helper'

describe Chore::Queues::PubSub do
  include_context 'fake pubsub objects'

  let(:topic_admin) { double('topic_admin') }
  let(:subscription_admin) { double('subscription_admin') }
  let(:topic_path) { "projects/test/topics/#{queue_name}" }
  let(:subscription_path) { "projects/test/subscriptions/#{subscription_name}" }

  before(:each) do
    allow(Chore::Queues::PubSub).to receive(:pubsub_client).and_return(pubsub_client)
    allow(Chore).to receive(:prefixed_queue_names).and_return([queue_name])
  end

  context "when managing queues" do
    before(:each) do
      allow(pubsub_client).to receive(:topic_admin).and_return(topic_admin)
      allow(pubsub_client).to receive(:subscription_admin).and_return(subscription_admin)
      allow(pubsub_client).to receive(:topic_path).with(queue_name).and_return(topic_path)
      allow(pubsub_client).to receive(:subscription_path).with(subscription_name).and_return(subscription_path)
    end
    it 'should create topics and subscriptions that are defined in its internal job name list' do
      expect(topic_admin).to receive(:create_topic).with(name: topic_path).and_return(topic)
      expect(subscription_admin).to receive(:create_subscription).with(
        name: subscription_path,
        topic: topic_path
      )
      Chore::Queues::PubSub.create_queues!
    end

    it 'should delete topics and subscriptions that are defined in its internal job name list' do
      expect(Chore.logger).to receive(:info).with("Chore Deleting Pub/Sub Topic and Subscription: #{queue_name}")
      expect(subscription_admin).to receive(:delete_subscription).with(subscription: subscription_path)
      expect(topic_admin).to receive(:delete_topic).with(topic: topic_path)
      
      Chore::Queues::PubSub.delete_queues!
    end

    context 'when handling delete errors' do
      it 'should continue deleting topic even if subscription delete fails' do
        allow(subscription_admin).to receive(:delete_subscription).and_raise(Google::Cloud::NotFoundError.new('Subscription not found'))
        expect(topic_admin).to receive(:delete_topic).with(topic: topic_path)
        expect(Chore.logger).to receive(:info).with("Chore Deleting Pub/Sub Topic and Subscription: #{queue_name}")
        expect(Chore.logger).to receive(:error).with("Deleting Subscription: #{queue_name} failed because Subscription not found")
        
        Chore::Queues::PubSub.delete_queues!
      end

      it 'should continue even if topic delete fails' do
        expect(subscription_admin).to receive(:delete_subscription).with(subscription: subscription_path)
        allow(topic_admin).to receive(:delete_topic).and_raise(Google::Cloud::NotFoundError.new('Topic not found'))
        expect(Chore.logger).to receive(:info).with("Chore Deleting Pub/Sub Topic and Subscription: #{queue_name}")
        expect(Chore.logger).to receive(:error).with("Deleting Topic: #{queue_name} failed because Topic not found")
        
        Chore::Queues::PubSub.delete_queues!
      end
    end

    context 'and checking for existing queues' do
      it 'checks for existing topics/subscriptions' do
        allow(pubsub_client).to receive(:topic_path).with(queue_name).and_return(topic_path)
        allow(pubsub_client).to receive(:subscription_path).with(subscription_name).and_return(subscription_path)
        expect(described_class).to receive(:existing_queues).and_return([])
        # Since existing_queues returns [], create_queues! will proceed to create topics/subscriptions
        allow(topic_admin).to receive(:create_topic).and_return(topic)
        allow(subscription_admin).to receive(:create_subscription)
        Chore::Queues::PubSub.create_queues!(true)
      end

      it 'raises an error if a topic/subscription does exist' do
        allow(described_class).to receive(:existing_queues).and_return([queue_name])
        expect{Chore::Queues::PubSub.create_queues!(true)}.to raise_error(RuntimeError)
      end

      it 'does not raise an error if a topic/subscription does not exist' do
        allow(topic_admin).to receive(:create_topic).and_return(topic)
        allow(subscription_admin).to receive(:create_subscription)
        allow(described_class).to receive(:existing_queues).and_return([])
        expect{Chore::Queues::PubSub.create_queues!(true)}.not_to raise_error
      end
    end

    context 'when handling already exists errors' do
      it 'should continue when topic already exists' do
        allow(topic_admin).to receive(:create_topic).and_raise(Google::Cloud::AlreadyExistsError.new('Topic already exists'))
        allow(subscription_admin).to receive(:create_subscription).and_return(subscriber)
        expect(Chore.logger).to receive(:info).with("Chore Creating Pub/Sub Topic and Subscription: #{queue_name}")
        expect(Chore.logger).to receive(:info).with("Topic already exists: Topic already exists")
        expect { Chore::Queues::PubSub.create_queues! }.not_to raise_error
      end

      it 'should continue when subscription already exists' do
        allow(topic_admin).to receive(:create_topic).and_return(topic)
        allow(subscription_admin).to receive(:create_subscription).and_raise(Google::Cloud::AlreadyExistsError.new('Subscription already exists'))
        expect(Chore.logger).to receive(:info).with("Chore Creating Pub/Sub Topic and Subscription: #{queue_name}")
        expect(Chore.logger).to receive(:info).with("Subscription already exists: Subscription already exists")
        expect { Chore::Queues::PubSub.create_queues! }.not_to raise_error
      end

      it 'should continue when both topic and subscription already exist' do
        allow(topic_admin).to receive(:create_topic).and_raise(Google::Cloud::AlreadyExistsError.new('Topic already exists'))
        allow(subscription_admin).to receive(:create_subscription).and_raise(Google::Cloud::AlreadyExistsError.new('Subscription already exists'))
        expect(Chore.logger).to receive(:info).with("Chore Creating Pub/Sub Topic and Subscription: #{queue_name}")
        expect(Chore.logger).to receive(:info).with("Topic already exists: Topic already exists")
        expect(Chore.logger).to receive(:info).with("Subscription already exists: Subscription already exists")
        expect { Chore::Queues::PubSub.create_queues! }.not_to raise_error
      end
    end
  end

  describe '.existing_queues' do
    it 'returns queues that exist when both publisher and subscriber calls succeed' do
      allow(pubsub_client).to receive(:publisher).with(queue_name).and_return(topic)
      allow(pubsub_client).to receive(:subscriber).with(queue_name).and_return(subscriber)
      expect(described_class.existing_queues).to eq([queue_name])
    end

    it 'filters out queues when publisher call raises NotFoundError' do
      allow(pubsub_client).to receive(:publisher).with(queue_name).and_raise(Google::Cloud::NotFoundError.new('Topic not found'))
      expect(described_class.existing_queues).to eq([])
    end

    it 'filters out queues when subscriber call raises NotFoundError' do
      allow(pubsub_client).to receive(:publisher).with(queue_name).and_return(topic)
      allow(pubsub_client).to receive(:subscriber).with(queue_name).and_raise(Google::Cloud::NotFoundError.new('Subscription not found'))
      expect(described_class.existing_queues).to eq([])
    end

    it 'filters out queues when publisher call raises Google::Cloud::NotFoundError' do
      allow(pubsub_client).to receive(:publisher).with(queue_name).and_raise(Google::Cloud::NotFoundError.new('Topic not found'))
      expect(described_class.existing_queues).to eq([])
    end

    it 'handles other errors gracefully' do
      allow(pubsub_client).to receive(:publisher).with(queue_name).and_raise(StandardError.new('Connection error'))
      expect(described_class.existing_queues).to eq([])
    end
  end
end 
