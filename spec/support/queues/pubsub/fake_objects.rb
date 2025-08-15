describe Chore::Queues::PubSub do
  RSpec.shared_context 'fake pubsub objects' do
    let(:queue_name) { 'test_queue' }
    let(:subscription_name) { "#{queue_name}-sub" }
    let(:project_id) { 'test-project' }

    let(:message_data) { {'class' => 'TestJob', 'args' => [1, 2, '3']}.to_json }
    let(:message_id) { 'message-id-123' }
    let(:ack_id) { 'ack-id-456' }

    let(:received_message) do
      double('Google::Cloud::PubSub::ReceivedMessage',
        message_id: message_id,
        ack_id: ack_id,
        data: message_data,
        delivery_attempt: 1,
        acknowledge!: true,
        modify_ack_deadline!: true
      )
    end

    let(:topic) do
      double('Google::Cloud::PubSub::Topic',
        name: queue_name,
        exists?: true,
        publish: received_message,
        create_subscription: subscription,
        delete: true
      )
    end

    let(:subscription) do
      double('Google::Cloud::PubSub::Subscription',
        name: subscription_name,
        exists?: true,
        deadline: 600,
        pull: [received_message],
        delete: true
      )
    end

    let(:pubsub_client) do
      topic_admin = double('topic_admin', 
        create_topic: topic,
        delete_topic: true
      )
      subscription_admin = double('subscription_admin', 
        create_subscription: subscription,
        delete_subscription: true
      )
      
      double('Google::Cloud::PubSub::Project',
        project_id: project_id,
        publisher: topic,
        subscriber: subscription,
        topic_admin: topic_admin,
        subscription_admin: subscription_admin,
        topic_path: "projects/#{project_id}/topics/#{queue_name}",
        subscription_path: "projects/#{project_id}/subscriptions/#{queue_name}-sub"
      )
    end
  end
end 