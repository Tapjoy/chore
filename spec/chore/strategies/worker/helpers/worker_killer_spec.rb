require 'spec_helper'
require 'get_process_mem'

describe Chore::Strategy::WorkerKiller do
  let(:memory_limit)    { 1024 }
  let(:request_limit)   { 100 }
  let(:check_cycle)     { 16 }
  let(:worker_killer)   { Chore::Strategy::WorkerKiller.new }
  let(:process_mem_obj) { double('process_mem_obj', bytes: 10) }

  context '#initialize' do
    it 'should initialize the WorkerKiller correctly' do
      allow(Chore.config).to receive(:memory_limit_bytes).and_return(memory_limit)
      allow(Chore.config).to receive(:request_limit).and_return(request_limit)
      allow(Chore.config).to receive(:check_cycle).and_return(check_cycle)

      wk = Chore::Strategy::WorkerKiller.new
      expect(wk.instance_variable_get(:@memory_limit)).to equal(memory_limit)
      expect(wk.instance_variable_get(:@request_limit)).to equal(request_limit)
      expect(wk.instance_variable_get(:@check_cycle)).to equal(check_cycle)
      expect(wk.instance_variable_get(:@check_count)).to equal(0)
      expect(wk.instance_variable_get(:@current_requests)).to equal(0)
    end
  end

  context '#check_memory' do
    before(:each) do
      allow(GetProcessMem).to receive(:new).and_return(process_mem_obj)
      worker_killer.instance_variable_set(:@memory_limit, memory_limit)
      worker_killer.instance_variable_set(:@check_cycle, check_cycle)
    end

    it 'should return nil when memory_limit is nil' do
      worker_killer.instance_variable_set(:@memory_limit, nil)
      expect(worker_killer.check_memory).to eq(nil)
    end

    it 'should increment the check count by 1' do
      worker_killer.instance_variable_set(:@check_count, 1)
      worker_killer.check_memory
      expect(worker_killer.instance_variable_get(:@check_count)).to eq(2)
    end

    context 'check_count equals check_cycle' do
      before(:each) do
        worker_killer.instance_variable_set(:@check_count, 15)
      end

      it 'should check memory' do
        expect(process_mem_obj).to receive(:bytes)
        worker_killer.check_memory
      end

      it 'should reset the check_count to zero' do
        allow(process_mem_obj).to receive(:bytes).and_return(0)
        worker_killer.check_memory
        expect(worker_killer.instance_variable_get(:@check_count)).to equal(0)
      end

      it 'should exit if the process mem exceeds the memory_limit' do
        allow(process_mem_obj).to receive(:bytes).and_return(2048)
        begin
          worker_killer.check_memory
        rescue SystemExit=>e
          expect(e.status).to eq(0)
        end
      end
    end
  end

  context '#check_requests' do
    before(:each) do
      worker_killer.instance_variable_set(:@request_limit, request_limit)
      worker_killer.instance_variable_set(:@current_requests, 0)
    end

    it 'should return nil when request_limit is nil' do
      worker_killer.instance_variable_set(:@request_limit, nil)
      expect(worker_killer.check_requests).to eq(nil)
    end

    it 'should increment current requests' do
      worker_killer.check_requests
      expect(worker_killer.instance_variable_get(:@current_requests)).to eq(1)
    end

    it 'should exit when current_requests exceeds request_limit' do
      worker_killer.instance_variable_set(:@current_requests, request_limit - 1)

      begin
        worker_killer.check_requests
      rescue SystemExit=>e
        expect(e.status).to eq(0)
      end
    end
  end
end