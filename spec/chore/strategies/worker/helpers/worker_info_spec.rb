require 'spec_helper'

describe Chore::Strategy::WorkerInfo do
  let(:socket)      { double('socket') }
  let(:worker_info) { Chore::Strategy::WorkerInfo.new(pid) }

  context '#initialize' do
    it 'should initialize the WorkerInfo with a socket' do
      wi = Chore::Strategy::WorkerInfo.new(socket)
      expect(wi.socket).to equal(socket)
      expect(wi.pid).to equal(nil)
    end
  end
end
