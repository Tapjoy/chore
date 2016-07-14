require 'spec_helper'
require 'socket'

describe Chore::Strategy::Ipc do
  class DummyClass
    include Chore::Strategy::Ipc
  end

  before(:each) do
    @dummy_instance = DummyClass.new
  end

  let(:socket)          { double('socket') }
  let(:connection)      { double('socket') }
  let(:message)         { "test message" }
  let(:encoded_message) { "#{[Marshal.dump(message).size].pack('L>')}#{Marshal.dump(message)}" }
  let(:socket_base)     { './prefork_worker_sock-' }
  let(:pid)             { '1' }
  let(:socket_file)     { socket_base + pid }

  describe '#create_master_socket' do
    before(:each) do
      allow(Process).to receive(:pid).and_return(pid)
    end

    it 'deletes socket file, if it already exists' do
      allow(File).to receive(:exist?).with(socket_file).and_return(true)
      allow(UNIXServer).to receive(:new).and_return(socket)
      allow(socket).to receive(:setsockopt).and_return(true)
      expect(File).to receive(:delete).with(socket_file)
      @dummy_instance.create_master_socket
    end

    it 'should create and return a new UnixServer object' do
      allow(File).to receive(:exist?).with(socket_file).and_return(false)
      allow(UNIXServer).to receive(:new).and_return(socket)
      allow(socket).to receive(:setsockopt).and_return(true)
      expect(@dummy_instance.create_master_socket).to eq(socket)
    end

    it 'should set the required socket options' do
      allow(File).to receive(:exist?).with(socket_file).and_return(false)
      allow(UNIXServer).to receive(:new).and_return(socket)
      expect(socket).to receive(:setsockopt).with(:SOCKET, :REUSEADDR, true)
      @dummy_instance.create_master_socket
    end
  end

  context '#child_connection' do
    it 'should accept a connection and return the connection socket' do
      expect(socket).to receive(:accept_nonblock).and_return(connection)
      expect(@dummy_instance.child_connection(socket)).to eq connection
    end
  end

  context '#send_msg' do
    it 'should raise an exception if the message is empty' do
      expect { @dummy_instance.send_msg(socket, nil) }.to raise_error('send_msg cannot send empty messages')
    end

    it 'should send a message with the predefined protocol (size of message + marshalled message)' do
      expect(socket).to receive(:send).with(encoded_message, 0)
      @dummy_instance.send_msg(socket, message)
    end
  end

  context '#read_msg' do
    before(:each) do
      allow(IO).to receive(:select).with([socket], nil, nil, 0.5).and_return([[socket], [], []])
    end

    it 'should return nil if the message size is missing' do
      allow(socket).to receive(:recv).and_return(nil)
      expect(@dummy_instance.read_msg(socket)).to eq(nil)
    end

    it 'should read a message with the predefined protocol (size of message + marshalled message)' do
      allow(socket).to receive(:recv).and_return(encoded_message)
      expect(@dummy_instance.read_msg(socket)).to eq(message)
    end

    it 'should raise an exception if the connection was dropped' do
      allow(socket).to receive(:recv).and_raise(Errno::ECONNRESET)
      expect { @dummy_instance.read_msg(socket) }.to raise_error(Errno::ECONNRESET)
    end
  end

  context '#add_worker_socket' do
    it 'should create and return a new UnixSocket object' do
      allow(UNIXSocket).to receive(:new).and_return(socket)
      allow(socket).to receive(:setsockopt).and_return(true)
      expect(@dummy_instance.add_worker_socket).to eq(socket)
    end

    it 'should set the required socket options' do
      allow(UNIXSocket).to receive(:new).and_return(socket)
      expect(socket).to receive(:setsockopt).with(:SOCKET, :REUSEADDR, true)
      @dummy_instance.add_worker_socket
    end
  end

  context '#clear_ready' do
    it 'should remove the ready signal from the the socket' do
      expect(socket).to receive(:gets)
      @dummy_instance.clear_ready(socket)
    end
  end

  context '#signal_ready' do
    it 'should set a ready signal on the socket' do
      expect(socket).to receive(:puts).with('R')
      @dummy_instance.signal_ready(socket)
    end
  end

  context '#select_sockets' do
    it 'should return a readable socket if one is found' do
      allow(IO).to receive(:select).with([socket], nil, [socket], 0.5).and_return([[socket], [], []])
      expect(@dummy_instance.select_sockets([socket], nil, 0.5)).to eq([[socket], [], []])
    end

    it 'should timeout and return no sockets if none are found within the timeout window' do
      expect(@dummy_instance.select_sockets(nil, nil, 0.1)).to eq(nil)
    end
  end
end

