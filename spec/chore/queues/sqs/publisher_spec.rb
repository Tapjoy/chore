require 'spec_helper'

module Chore
  describe Queues::SQS::Publisher do
    let(:job) { {'class' => 'TestJob', 'args'=>[1,2,'3']}}
    let(:queue_name) { 'test_queue' }
    let(:queue_url) {"http://www.queue_url.com/test_queue"}
    let(:queue) { double('queue', :send_message => nil) }
    let(:sqs) do
      double('sqs', :queues => double('queues', :named => queue, :url_for => queue_url, :[] => queue))
    end
    let(:publisher) { Queues::SQS::Publisher.new }
    let(:pool) { double("pool") }

    before(:each) do
      AWS::SQS.stub(:new).and_return(sqs)
    end

    it 'should configure sqs' do
      Chore.config.stub(:aws_access_key).and_return('key')
      Chore.config.stub(:aws_secret_key).and_return('secret')

      AWS::SQS.should_receive(:new).with(
        :access_key_id => 'key',
        :secret_access_key => 'secret',
        :logger => Chore.logger,
        :log_level => :debug
      )
      publisher.publish(queue_name,job)
    end

    it 'should create send an encoded message to the specified queue' do
      queue.should_receive(:send_message).with(job.to_json)
      publisher.publish(queue_name,job)
    end

    it 'should lookup the queue when publishing' do
      sqs.queues.should_receive(:url_for).with('test_queue')
      publisher.publish('test_queue', job)
    end

    it 'should lookup multiple queues if specified' do
      sqs.queues.should_receive(:url_for).with('test_queue')
      sqs.queues.should_receive(:url_for).with('test_queue2')
      publisher.publish('test_queue', job)
      publisher.publish('test_queue2', job)
    end

    it 'should only lookup a named queue once' do
      sqs.queues.should_receive(:url_for).with('test_queue').once
      2.times { publisher.publish('test_queue', job) }
    end

    context "batch sending" do
      let(:queue)       { Queue.new }
      let(:thread_pool) { double("Chore::Queues::SQS::BatchSendingPool") }
      before do
        Chore.config.stub(:send_in_batches).and_return(true)
      end
      it "should create a pool" do
        Thread::Pool.should_receive(:new).with(5).and_return(thread_pool)
        publisher.publish('test_queue',job)
      end

      context "context" do
        before do
          Chore::Queues::SQS::BatchSendingPool.stub(:new).and_return(thread_pool)
          thread_pool.stub(:ready?).and_return(true)
          queue << {:message_body=>job.to_json}
          publisher.class.class_variable_set(:@@messages, { 'test_queue' => queue})
          publisher.class.class_variable_set(:@@thread_pool, thread_pool)
          publisher.class.class_variable_set(:@@running, true)
        end
        it "should drain a queue" do
          thread_pool.should_receive(:process).at_least(:once)
          publisher.class.pass_batch_to_thread_pool('test_queue')
        end
      end

      context "after init" do
        before do
          Chore::Queues::SQS::BatchSendingPool.stub(:new).and_return(thread_pool)
          publisher.class.class_variable_set(:@@messages, {})
          publisher.class.class_variable_set(:@@thread_pool, nil)
          publisher.class.class_variable_set(:@@running, false)
        end

        it "should enqueue into the class level message queue" do
          publisher.publish('test_queue', job)
          publisher.class.class_variable_get(:@@messages)['test_queue'].pop.should == {:message_body => job.to_json}
        end

        it "should start a background timer thread" do
          publisher.class.should_receive(:spawn_timer)
          publisher.publish('test_queue', job)
        end
      end
    end

    describe '#reset_connection!' do
      it 'should reset the connection after a call to reset_connection!' do
        AWS::Core::Http::ConnectionPool.stub(:pools).and_return([pool])
        pool.should_receive(:empty!)
        Chore::Queues::SQS::Publisher.reset_connection!
        publisher.queue(queue_name)
      end
  
      it 'should not reset the connection between calls' do
        sqs = publisher.queue(queue_name)
        sqs.should be publisher.queue(queue_name)
      end
  
      it 'should reconfigure sqs' do
        Chore::Queues::SQS::Publisher.reset_connection!
        AWS::SQS.should_receive(:new)
        publisher.queue(queue_name)
      end
    end
  end
end
