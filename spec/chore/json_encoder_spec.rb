require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Chore::JsonEncoder do
  it 'should have an encode method' do
    subject.should respond_to :encode
  end

  it 'should have a decode method' do
    subject.should respond_to :decode
  end
end
