require 'spec_helper'

describe Chore::Strategy::WorkerInfo do
  let(:pid)         { 1 }
  let(:worker_info) { Chore::Strategy::WorkerInfo.new(pid) }

  context '#initialize' do
    it 'should initialize the WorkerInfo with a pid' do
      wi = Chore::Strategy::WorkerInfo.new(pid)
      expect(wi.pid).to equal(pid)
      expect(wi.socket).to equal(nil)
    end
  end
end
