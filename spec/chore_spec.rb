require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Chore do
  before(:each) do
    Chore.clear_hooks!
  end
  it 'should allow you to add a hook' do
    blk = proc { true }
    Chore.add_hook(:before_perform,&blk)
    Chore.hook_for(:before_perform).should == blk
  end

  it 'should call a hook if it exists' do
    blk = proc { raise StandardError }
    Chore.add_hook(:before_perform,&blk)
    expect { Chore.run_hook_for(:before_perform) }.to raise_error
  end

  it 'should not call a hook if it doesn\'t exist' do
    blk = proc { raise StandardError }
    expect { Chore.run_hook_for(:before_perform) }.to_not raise_error
  end
end
