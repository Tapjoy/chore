require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Chore do
  before(:each) do
    Chore.clear_hooks!
  end
  it 'should allow you to add a hook' do
    blk = proc { true }
    Chore.add_hook(:before_perform,&blk)
    Chore.hooks_for(:before_perform).first.should == blk
  end

  it 'should call a hook if it exists' do
    blk = proc { raise StandardError }
    Chore.add_hook(:before_perform,&blk)
    expect { Chore.run_hooks_for(:before_perform) }.to raise_error
  end

  it 'should not call a hook if it doesn\'t exist' do
    blk = proc { raise StandardError }
    expect { Chore.run_hooks_for(:before_perform) }.to_not raise_error
  end

  it 'should pass args to the block if present' do
    blk = proc {|*args| true }
    blk.should_receive(:call).with('1','2',3)
    Chore.add_hook(:an_event,&blk)
    Chore.run_hooks_for(:an_event, '1','2',3)
  end

  it 'should support multiple hooks for an event' do
    blk = proc { true }
    blk.should_receive(:call).twice
    Chore.add_hook(:before_perform,&blk)
    Chore.add_hook(:before_perform,&blk)

    Chore.run_hooks_for(:before_perform)
  end

  it 'should set configuration' do
    Chore.configure {|c| c.test_config_option = 'howdy' }
    Chore.config.test_config_option.should == 'howdy'
  end

  context "when managing queues" do
    let(:fake_sqs) {double(Object)}
    let(:fake_queue_collection) {double(Object)}
    let(:queue_name) {"test"}
    let(:queue_url) {"http://amazon.sqs.url/queues/#{queue_name}"}
    let(:fake_queue) {double(Object)}

    before(:each) do
      AWS::SQS.stub(:new).and_return(fake_sqs)
      Chore.stub(:prefixed_queue_names) {[queue_name]}
      fake_queue.stub(:delete)
  
      fake_queue_collection.stub(:[]) do |key|
        fake_queue
      end
  
      fake_queue_collection.stub(:create)
      fake_sqs.stub(:queues).and_return(fake_queue_collection)
      fake_queue_collection.stub(:url_for).with(queue_name).and_return(queue_url)
    end

    it 'should create queues that are defined in its internal job name list' do
      #Only one job defined in the spec suite
      fake_queue_collection.should_receive(:create)
      Chore.create_queues!
    end

    it 'should delete queues that are defined in its internal job name list' do
      #Only one job defined in the spec suite
      fake_queue.should_receive(:delete)
      Chore.delete_queues!
    end
  end
end
