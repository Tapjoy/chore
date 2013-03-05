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


end
