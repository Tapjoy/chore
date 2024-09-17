require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

class TestHooks
  include Chore::Hooks
end

describe Chore::Hooks do
  let(:test_instance){ TestHooks.new }
  it 'should respond_to run_hooks_for' do
    expect(test_instance).to respond_to(:run_hooks_for)
  end

  it 'should call a defined hook' do
    expect(test_instance).to receive(:before_perform_test).and_return(true)
    test_instance.run_hooks_for(:before_perform)
  end

  it 'should call multiple defined hooks' do
    3.times do |i|
      expect(test_instance).to receive(:"before_perform_test#{i}").and_return(true)
    end
    test_instance.run_hooks_for(:before_perform)
  end

  it 'should bubble up raised exceptions' do
    expect(test_instance).to receive(:"before_perform_raise").and_raise(RuntimeError)
    expect { test_instance.run_hooks_for(:before_perform) }.to raise_error(RuntimeError)
  end

  describe 'global hooks' do
    before(:each) do
      Chore.clear_hooks!
      Chore.add_hook(:test_hook,&callback)
    end

    let(:callback) { proc { true } }

    it 'should call a global hook' do
      expect(callback).to receive(:call).once
      test_instance.run_hooks_for(:test_hook)
    end

  end
end
