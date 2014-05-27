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

  it 'should support passing blocks' do
    runner = proc { }

    blk = proc { true }
    blk.should_receive(:call) do |&arg1|
      arg1.should_not be_nil
    end
    Chore.add_hook(:around_perform,&blk)

    Chore.run_hooks_for(:around_perform, &runner)
  end

  it 'should call passed block' do
    Chore.add_hook(:around_perform) do |&blk|
      blk.call
    end

    run = false
    Chore.run_hooks_for(:around_perform) { run = true }
    run.should be_true
  end

  it 'should call passed blocks even if there are no hooks' do
    run = false
    Chore.run_hooks_for(:around_perform) { run = true }
    run.should be_true
  end

  it 'should set configuration' do
    Chore.configure {|c| c.test_config_option = 'howdy' }
    Chore.config.test_config_option.should == 'howdy'
  end

  describe 'reopen_logs' do
    let(:open_files) do
      [
        mock('file', :closed? => false, :reopen => nil, :sync= => nil, :path => '/a'),
        mock('file2', :closed? => false, :reopen => nil, :sync= => nil, :path => '/b')
      ]
    end
    let(:closed_files) do
      [mock('file3', :closed? => true)]
    end
    let(:files) { open_files + closed_files }

    before(:each) do
      ObjectSpace.stub(:each_object).and_yield(open_files[0]).and_yield(open_files[1])
    end

    it 'should look up all instances of files' do
      ObjectSpace.should_receive(:each_object).with(File)
      Chore.reopen_logs
    end

    it 'should reopen files that are not closed' do
      open_files.each do |file|
        file.should_receive(:reopen).with(file.path, 'a+')
      end
      Chore.reopen_logs
    end

    it 'should sync files' do
      open_files.each do |file|
        file.should_receive(:sync=).with(true)
      end
      Chore.reopen_logs
    end
  end
end
