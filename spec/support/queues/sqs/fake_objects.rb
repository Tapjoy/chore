describe Chore::Queues::SQS do
  RSpec.shared_context 'fake objects' do
    let(:queue_name) { 'test_queue' }
    let(:queue_url) { "http://amazon.sqs.url/queues/#{queue_name}" }

    let(:queue) do
      double(Aws::SQS::Queue,
        attributes: {'VisibilityTimeout' => rand(10)}
      )
    end

    let(:sqs) do
      double(Aws::SQS::Client,
        get_queue_url: double(Aws::SQS::Types::GetQueueUrlResult, :queue_url => queue_url),
      )
    end
  end
end
