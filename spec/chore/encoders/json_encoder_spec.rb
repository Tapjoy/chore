require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe Chore::Encoder::JsonEncoder do
  it 'should have an encode method' do
    expect(subject).to respond_to :encode
  end

  it 'should have a decode method' do
    expect(subject).to respond_to :decode
  end
end
