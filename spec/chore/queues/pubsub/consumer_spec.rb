require 'spec_helper'

describe Chore::Queues::PubSub::Consumer do
  include_context 'fake pubsub objects'

  let(:options) { {} }
  let(:consumer) { Chore::Queues::PubSub::Consumer.new(queue_name) }
  let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']} }
  let(:backoff_func) { Proc.new { 2 + 2 } }

  # Since a message handler is required (but not validated), this convenience method lets us
  # effectively stub the block.
  def consume(&block)
    block = Proc.new{} unless block_given?
    consumer.consume(&block)
  end

  before do
    allow(Chore::Queues::PubSub).to receive(:pubsub_client).and_return(pubsub_client)
    allow(subscription).to receive(:pull).and_return([received_message])
  end

  describe "consuming messages" do
    before do
      allow(consumer).to receive(:running?).and_return(true, false)
    end

    context "should create objects for interacting with the Pub/Sub API" do
      it 'should create a pubsub client' do
        expect(subscription).to receive(:pull)
        consume
      end

      it "should only create a pubsub client when one doesn't exist" do
        allow(consumer).to receive(:running?).and_return(true, true, true, true, false, true, true)
        expect(Chore::Queues::PubSub).to receive(:pubsub_client).exactly(:once)
        consume
      end

      it 'should look up the subscription based on the queue name' do
        expect(pubsub_client).to receive(:subscription).with(subscription_name)
        consume
      end

      it 'should create a subscription object' do
        expect(consumer.send(:subscription)).to_not be_nil
        consume
      end
    end

    context "should receive a message from the subscription" do
      it 'should use the default size of 10 when no queue_polling_size is specified' do
        expect(subscription).to receive(:pull).with(max: 10).and_return([received_message])
        consume
      end

      it 'should respect the queue_polling_size when specified' do
        allow(Chore.config).to receive(:queue_polling_size).and_return(5)
        expect(subscription).to receive(:pull).with(max: 5)
        consume
      end

      it 'should respect Pub/Sub max limit of 1000 messages' do
        allow(Chore.config).to receive(:queue_polling_size).and_return(2000)
        expect(subscription).to receive(:pull).with(max: 1000)
        consume
      end
    end

    context 'with no messages' do
      before do
        allow(consumer).to receive(:handle_messages).and_return([])
      end

      it 'should sleep' do
        expect(consumer).to receive(:sleep).with(1)
        consume
      end
    end

    context 'with messages' do
      before do
        allow(consumer).to receive(:duplicate_message?).and_return(false)
        allow(subscription).to receive(:pull).and_return([received_message])
        allow(Time).to receive(:now).and_return(Time.utc(2024, 5, 10, 12, 0, 0))
      end

      it "should check the uniqueness of the message" do
        expect(consumer).to receive(:duplicate_message?)
        consume
      end

      let(:received_timestamp) { Time.utc(2024, 5, 10, 12, 0, 0) }

      it "should yield the message to the handler block" do
        expect { |b| consume(&b) }
          .to yield_with_args(
                received_message.message_id,
                received_message.ack_id,
                queue_name,
                subscription.ack_deadline_seconds,
                received_message.data,
                0, # delivery_attempt - 1 (1 - 1 = 0)
                received_timestamp
              )
      end

      it 'should not sleep' do
        expect(consumer).to_not receive(:sleep)
        consume
      end

      context 'with duplicates' do
        before do
          allow(consumer).to receive(:duplicate_message?).and_return(true)
        end

        it 'should not yield for a dupe message' do
          expect {|b| consume(&b) }.not_to yield_control
        end
      end

      context 'with delivery attempt count' do
        before do
          allow(received_message).to receive(:delivery_attempt).and_return(3)
        end

        it 'should calculate attempt count as delivery_attempt - 1' do
          expect { |b| consume(&b) }
            .to yield_with_args(
                  received_message.message_id,
                  received_message.ack_id,
                  queue_name,
                  subscription.ack_deadline_seconds,
                  received_message.data,
                  2, # delivery_attempt - 1 (3 - 1 = 2)
                  received_timestamp
                )
        end
      end

      context 'with nil delivery attempt (older messages)' do
        before do
          allow(received_message).to receive(:delivery_attempt).and_return(nil)
        end

        it 'should default to attempt count of 0' do
          expect { |b| consume(&b) }
            .to yield_with_args(
                  received_message.message_id,
                  received_message.ack_id,
                  queue_name,
                  subscription.ack_deadline_seconds,
                  received_message.data,
                  0, # (nil || 1) - 1 = 0
                  received_timestamp
                )
        end
      end
    end

    context 'on subscription lookup failure' do
      before(:each) do
        allow(consumer).to receive(:verify_connection!).and_raise(Google::Cloud::NotFoundError.new('Subscription not found'))
      end

      it 'should raise exception' do
        expect { consume }.to raise_error(Chore::TerribleMistake)
      end
    end

    context 'on gcp credential failure' do
      before(:each) do
        allow(consumer).to receive(:verify_connection!).and_raise(Google::Cloud::PermissionDeniedError.new('Permission denied'))
      end

      it 'should raise exception' do
        expect { consume }.to raise_error(Chore::TerribleMistake)
      end
    end

    context 'on unexpected failure' do
      before(:each) do
        allow(consumer).to receive(:verify_connection!).and_raise(StandardError.new('Connection error'))
      end

      it 'should raise exception' do
        expect { consume }.to raise_error(Chore::TerribleMistake)
      end
    end
  end

  describe "completing work" do
    before do
      # Set up current messages for the complete method to work
      consumer.instance_variable_set(:@current_messages, [received_message])
    end

    it 'acknowledges the message in the subscription' do
      expect(received_message).to receive(:acknowledge!)
      consumer.complete(received_message.message_id, received_message.ack_id)
    end

    it 'handles missing message gracefully' do
      expect { consumer.complete('unknown-id', 'unknown-ack') }.not_to raise_error
    end
  end

  describe '#delay' do
    let(:item) { Chore::UnitOfWork.new(received_message.message_id, received_message.ack_id, queue_name, 600, received_message.data, 0, consumer) }

    before do
      # Set up current messages for the delay method to work
      consumer.instance_variable_set(:@current_messages, [received_message])
    end

    it 'modifies the ack deadline of the message' do
      delay_seconds = backoff_func.call(item)
      expect(received_message).to receive(:modify_ack_deadline!).with(delay_seconds)
      consumer.delay(item, backoff_func)
    end

    it 'returns the delay value' do
      delay_seconds = backoff_func.call(item)
      result = consumer.delay(item, backoff_func)
      expect(result).to eq(delay_seconds)
    end

    it 'handles missing message gracefully' do
      unknown_item = Chore::UnitOfWork.new('unknown-id', 'unknown-ack', queue_name, 600, 'data', 0, consumer)
      expect { consumer.delay(unknown_item, backoff_func) }.not_to raise_error
    end
  end

  describe '#reject' do
    it 'should be implemented but do nothing (Pub/Sub handles redelivery automatically)' do
      expect { consumer.reject('message-id') }.not_to raise_error
    end
  end

  describe '#reset_connection!' do
    it 'should reset the connection after a call to reset_connection!' do
      # First call establishes the connection
      consumer.send(:subscription)
      
      # Reset connection
      Chore::Queues::PubSub::Consumer.reset_connection!
      
      # Should recreate client
      expect(Chore::Queues::PubSub).to receive(:pubsub_client).and_return(pubsub_client)
      consumer.send(:subscription)
    end

    it 'should not reset the connection between calls' do
      expect(Chore::Queues::PubSub).to receive(:pubsub_client).once.and_return(pubsub_client)
      s = consumer.send(:subscription)
      expect(consumer.send(:subscription)).to be(s)
    end

    it 'should reconfigure pubsub client' do
      allow(consumer).to receive(:running?).and_return(true, false)
      allow_any_instance_of(Chore::DuplicateDetector).to receive(:found_duplicate?).and_return(false)

      allow(subscription).to receive(:pull).and_return([received_message])

      consume

      Chore::Queues::PubSub::Consumer.reset_connection!
      allow(Chore::Queues::PubSub).to receive(:pubsub_client).and_return(pubsub_client)

      expect(consumer).to receive(:running?).and_return(true, false)
      consume
    end
  end

  describe '#verify_connection!' do
    it 'should verify subscription exists' do
      expect(subscription).to receive(:exists?).and_return(true)
      expect { consumer.verify_connection! }.not_to raise_error
    end

    it 'should raise error if subscription does not exist' do
      allow(subscription).to receive(:exists?).and_return(false)
      expect { consumer.verify_connection! }.to raise_error
    end
  end

  describe 'queue timeout' do
    it 'should return subscription ack deadline' do
      expect(consumer.send(:queue_timeout)).to eq(600)
    end

    it 'should default to 600 seconds if ack_deadline_seconds is nil' do
      allow(subscription).to receive(:ack_deadline_seconds).and_return(nil)
      expect(consumer.send(:queue_timeout)).to eq(600)
    end
  end
end 