require 'spec_helper'

class TestJob2
  include Chore::Job
end

describe Chore::CLI do

  after :all do
    #This is here because the CLI specs mess with config and cause problems for some of the job specs...
    #Proper solution incoming
    Chore::CLI.instance.parse([])
  end

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
    options = cli.parse_config_file(file)
    cli.registered_opts['key_name'].should == {:args => args}
    options[:key_name].should == 'some_value'
  end

  it 'should handle ERB tags in a config file' do
    file = StringIO.new("--key-name=<%= 'erb_inserted_value' %>\n--other-key=<%= 'second_val' %>")
    File.stub(:read).and_return(file.read)

    cli = Chore::CLI.instance
    cli.register_option "key_name", '-k', '--key-name SOME_VALUE', "Some description"
    cli.register_option "other_key", '-o', '--other-key SOME_VALUE', "Some description"
    options = cli.parse_config_file(file)
    options[:key_name].should == 'erb_inserted_value'
    options[:other_key].should == 'second_val'
  end

  context 'queue mananagement' do
    let(:cli) { Chore::CLI.instance }
    before(:each) do
      TestJob.queue_options :name => 'test_queue', :publisher => Chore::Publisher
      TestJob2.queue_options :name => 'test2', :publisher => Chore::Publisher
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

    it 'should honor --queue-prefix when processing all queues' do
      cli.parse(['--queue-prefix=prefixey'])
      Chore.config.queues.should include('prefixey_test')
    end

    it 'should raise an exception if both --queues and --except are specified' do
      expect { cli.parse(['--except=something','--queues=something,else']) }.to raise_error(ArgumentError)
    end

    it 'should raise an exception if no queues are found' do
      Chore::Job.job_classes.clear
      expect { cli.parse([]) }.to raise_error(ArgumentError)
    end
  end
end
