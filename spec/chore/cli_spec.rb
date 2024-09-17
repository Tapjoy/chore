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
      expect(cli.registered_opts['option_name']).to eq({:args => args})
    end

    it 'should allow configuration options to come from a file' do
      file = StringIO.new("--key-name=some_value")
      allow(File).to receive(:read).and_return(file.read)

      args = ['-k', '--key-name SOME_VALUE', "Some description"]
      Chore::CLI.register_option "key_name", *args
      options = cli.parse_config_file(file)
      expect(cli.registered_opts['key_name']).to eq({:args => args})
      expect(options[:key_name]).to eq('some_value')
    end

    it 'should handle ERB tags in a config file' do
      file = StringIO.new("--key-name=<%= 'erb_inserted_value' %>\n--other-key=<%= 'second_val' %>")
      allow(File).to receive(:read).and_return(file.read)

      Chore::CLI.register_option "key_name", '-k', '--key-name SOME_VALUE', "Some description"
      Chore::CLI.register_option "other_key", '-o', '--other-key SOME_VALUE', "Some description"
      options = cli.parse_config_file(file)
      expect(options[:key_name]).to eq('erb_inserted_value')
      expect(options[:other_key]).to eq('second_val')
    end
  end

  context 'queue mananagement' do
    before(:each) do
      TestJob.queue_options :name => 'test_queue', :publisher => Chore::Publisher
      TestJob2.queue_options :name => 'test2', :publisher => Chore::Publisher
      cli.send(:options).delete(:queues)
      allow(cli).to receive(:validate!)
      allow(cli).to receive(:boot_system)
    end

    after :all do
      #Removing the prefix due to spec idempotency issues in job spec
      Chore.config.queue_prefix = nil
    end

    it 'should detect queues based on included jobs' do
      cli.parse([])
      expect(Chore.config.queues).to include('test_queue')
    end

    it 'should honor --except when processing all queues' do
      cli.parse(['--except=test_queue'])
      expect(Chore.config.queues).not_to include('test_queue')
    end

    it 'should honor --queue-prefix when processing all queues' do
      cli.parse(['--queue-prefix=prefixey_'])
      expect(Chore.config.queues).to include('prefixey_test2')
    end

    context 'when provided duplicate queues' do
      let(:queue_options) {['--queues=test2,test2']}
      before :each do
        cli.parse(queue_options)
      end

      it 'should not have duplicate queues' do
        expect(Chore.config.queues.count).to eq(1)
      end
    end

    context 'when provided a queue for which there is no job class' do
      let(:queue_options) {['--queues=test2,test3']}

      it 'should raise an error' do
        expect {cli.parse(queue_options)}.to raise_error(StandardError)
      end
    end

    context 'when both --queue_prefix and --queues have been provided' do
      let(:queue_options) {['--queue-prefix=prefixy_', '--queues=test2']}
      before :each do
        cli.parse(queue_options)
      end

      it 'should honor --queue_prefix' do
        total_queues = Chore.config.queues.count
        prefixed_queues = Chore.config.queues.count {|item| item.start_with?("prefixy_")}
        expect(prefixed_queues).to eq(total_queues)
      end

      it 'should prefix the names of the specified queues' do
        expect(Chore.config.queues).to include('prefixy_test2')
      end

      it 'should not prefix the names of queues that were not specified' do
        expect(Chore.config.queues).not_to include('prefixy_test_queue')
      end

      it 'should not have a queue without the prefix' do
        expect(Chore.config.queues).not_to include('test2')
      end

      it 'should not have a queue that was not specified' do
        expect(Chore.config.queues).not_to include('test_queue')
      end
    end

    it 'should raise an exception if both --queues and --except are specified' do
      expect { cli.parse(['--except=something','--queues=something,else']) }.to raise_error(ArgumentError)
    end

    context "when no queues are found" do
      before :each do
        allow(Chore::Job).to receive(:job_classes).and_return([])
      end

      it 'should raise an exception' do
        expect { cli.parse([]) }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#parse" do
    let(:cli) do
      Chore::CLI.send(:new).tap do |cli|
        cli.send(:options).clear
        allow(cli).to receive(:validate!)
        allow(cli).to receive(:boot_system)
        allow(cli).to receive(:detect_queues)
      end
    end

    let(:config) { cli.parse(command); Chore.config }

    context "--consumer-strategy" do
      let(:command) { ["--consumer-strategy=Chore::Strategy::SingleConsumerStrategy"] }

      it "should set the consumer class" do
        expect(config.consumer_strategy).to eq(Chore::Strategy::SingleConsumerStrategy)
      end
    end

    context "--payload_handler" do
      let(:command) {["--payload_handler=Chore::Job"]}

      it "should set the payload handler class" do
        expect(config.payload_handler).to eq(Chore::Job)
      end
    end

    describe '--shutdown-timeout' do
      let(:command) { ["--shutdown-timeout=#{amount}"] }
      subject { config.shutdown_timeout }

      context 'given a numeric value' do
        let(:amount)  { '10.0' }

        it 'is that amount' do
          expect(subject).to eq(amount.to_f)
        end
      end

      context 'given no value' do
        let(:command) { [] }
        it 'is the default value, 120 seconds' do
          expect(subject).to eq(120.0)
        end
      end
    end

    describe '--consumer_sleep_interval' do
      let(:command) {["--consumer-sleep-interval=#{amount}"]}
      subject {config.consumer_sleep_interval}

      context 'given an integer value' do
        let(:amount)  { '10' }

        it 'is that amount' do
          expect(subject).to eq(amount.to_i)
        end
      end

      context 'given a float value' do
        let(:amount)  { '0.5' }

        it 'is that amount' do
          expect(subject).to eq(amount.to_f)
        end
      end

      context 'given no value' do
        let(:command) { [] }
        it 'is the default value, 1' do
          expect(subject).to eq(1)
        end
      end
    end

    describe '--max-attempts' do
      let(:command) { ["--max-attempts=#{amount}"] }
      subject { config.max_attempts }

      context 'given a numeric value' do
        let(:amount)  { '10' }

        it 'is that amount' do
          expect(subject).to eq(amount.to_i)
        end
      end

      context 'given no value' do
        let(:command) { [] }
        it 'is the default value, infinity' do
          expect(subject).to eq(1.0 / 0.0)
        end
      end
    end
  end

end
