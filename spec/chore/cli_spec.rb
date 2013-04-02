require 'spec_helper'

describe Chore::CLI do
  it 'should allow configuration options to be registered externally' do
    args = ['some','args']
    Chore::CLI.register_option('option_name',*args)
    Chore::CLI.instance.registered_opts['option_name'].should == {:args => args}
  end

  it 'should allow configuration options to come from a file' do
    file = StringIO.new("--key-name=some_value")
    File.stub(:read).and_return(file.read)

    args = ['-k', '--key-name SOME_VALUE', "Some description"]
    cli = Chore::CLI.instance
    cli.register_option "key_name", *args
    cli.parse_config_file(file)
    cli.registered_opts['key_name'].should == {:args => args}
  end

  it 'should handle ERB tags in a config file' do
    file = StringIO.new("--key-name=<%= 'erb_inserted_value' %>")
    File.stub(:read).and_return(file.read)

    args = ['-k', '--key-name SOME_VALUE', "Some description"]
    cli = Chore::CLI.instance
    cli.register_option "key_name", *args
    options = cli.parse_config_file(file)
    options[:key_name].should == 'erb_inserted_value'
  end

  context 'queue mananagement' do
    let(:cli) { Chore::CLI.instance }
    before(:each) do
      TestJob.queue_options :name => 'test_queue', :publisher => Chore::Publisher
      cli.send(:options).delete(:queues) 
      cli.stub(:validate!)
      cli.stub(:boot_system)
    end

    it 'should detect queues based on included jobs' do
      cli.parse([])
      Chore.config.queues.should include('test_queue')
    end

    it 'should honor --except when processing all queues' do
      cli.parse(['--except=test_queue'])
      Chore.config.queues.should_not include('test_queue')
    end

    it 'should raise an exception if both --queues and --except are specified' do
      expect { cli.parse(['--except=something','--queues=something,else']) }.to raise_error(ArgumentError)
    end
  end
end
