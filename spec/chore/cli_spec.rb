require 'spec_helper'

class TestJob2
  include Chore::Job
end

describe Chore::CLI do
  let(:cli) { Chore::CLI.send(:new) }

  describe ".register_option" do
    let(:cli) { Chore::CLI.instance }

    it 'should allow configuration options to be registered externally' do
      args = ['some','args']
      Chore::CLI.register_option('option_name',*args)
      cli.registered_opts['option_name'].should == {:args => args}
    end

    it 'should allow configuration options to come from a file' do
      file = StringIO.new("--key-name=some_value")
      File.stub(:read).and_return(file.read)

      args = ['-k', '--key-name SOME_VALUE', "Some description"]
      Chore::CLI.register_option "key_name", *args
      options = cli.parse_config_file(file)
      cli.registered_opts['key_name'].should == {:args => args}
      options[:key_name].should == 'some_value'
    end

    it 'should handle ERB tags in a config file' do
      file = StringIO.new("--key-name=<%= 'erb_inserted_value' %>\n--other-key=<%= 'second_val' %>")
      File.stub(:read).and_return(file.read)

      Chore::CLI.register_option "key_name", '-k', '--key-name SOME_VALUE', "Some description"
      Chore::CLI.register_option "other_key", '-o', '--other-key SOME_VALUE', "Some description"
      options = cli.parse_config_file(file)
      options[:key_name].should == 'erb_inserted_value'
      options[:other_key].should == 'second_val'
    end
  end

  context 'queue mananagement' do
    before(:each) do
      TestJob.queue_options :name => 'test_queue', :publisher => Chore::Publisher
      TestJob2.queue_options :name => 'test2', :publisher => Chore::Publisher
      cli.send(:options).delete(:queues)
      cli.stub(:validate!)
      cli.stub(:boot_system)
    end

    after :all do
      #Removing the prefix due to spec idempotency issues in job spec
      Chore.config.queue_prefix = nil
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
      Chore.config.queues.should include('prefixey_test2')
    end

    it 'should raise an exception if both --queues and --except are specified' do
      expect { cli.parse(['--except=something','--queues=something,else']) }.to raise_error(ArgumentError)
    end

    it 'should raise an exception if no queues are found' do
      Chore::Job.job_classes.clear
      expect { cli.parse([]) }.to raise_error(ArgumentError)
    end
  end

  describe "#parse" do
    let(:cli) do
      Chore::CLI.send(:new).tap do |cli|
        cli.send(:options).clear
        cli.stub(:validate!)
        cli.stub(:boot_system)
        cli.stub(:detect_queues)
      end
    end

    let(:config) { cli.parse(command); Chore.config }

    context "--consumer-strategy" do
      let(:command) { ["--consumer-strategy=Chore::Strategy::SingleConsumerStrategy"] }

      it "should set the consumer class" do
        config.consumer_strategy.should == Chore::Strategy::SingleConsumerStrategy
      end
    end
  end
end
