require 'spec_helper'

describe Chore::Strategy::Batcher do
  let(:batch_size) { 5 }
  let(:callback) { double("callback") }
  subject do
    batcher = Chore::Strategy::Batcher.new(batch_size)
    batcher.callback = callback
    batcher
  end

  context 'with no items' do
    it 'should not be ready' do
      subject.should_not be_ready
    end

    it 'should not invoke the callback when executed' do
      callback.should_not_receive(:call)
      subject.execute
    end

    it 'should not invoke the callback when force-executed' do
      callback.should_not_receive(:call)
      subject.execute(true)
    end

    it 'should not invoke callback when adding a new item' do
      callback.should_not_receive(:call)
      subject.add('test')
    end
  end

  context 'with partial batch completed' do
    let(:batch) { ['test'] * 3 }

    before(:each) do
      subject.batch = batch.dup
    end

    it 'should not be ready' do
      subject.should_not be_ready
    end

    it 'should not invoke callback when executed' do
      callback.should_not_receive(:call)
      subject.execute
    end

    it 'should invoke callback when force-executed' do
      callback.should_receive(:call).with(batch)
      subject.execute(true)
    end

    it 'should invoke callback when add completes the batch' do
      subject.add('test')
      callback.should_receive(:call).with(['test'] * 5)
      subject.add('test')
    end
  end

  context 'with batch completed' do
    let(:batch) { ['test'] * 5 }

    before(:each) do
      subject.batch = batch.dup
    end

    it 'should be ready' do
      subject.should be_ready
    end

    it 'should invoke callback when executed' do
      callback.should_receive(:call).with(batch)
      subject.execute
    end

    it 'should invoke callback when force-executed' do
      callback.should_receive(:call).with(batch)
      subject.execute(true)
    end

    it 'should invoke callback with subset-only when added to' do
      callback.should_receive(:call).with(['test'] * 5)
      subject.add('test')
    end

    it 'should leave remaining batch when added to' do
      callback.stub(:call)
      subject.add('test')
      subject.batch.should == ['test']
    end
  end
end