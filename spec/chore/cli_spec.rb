require 'spec_helper'

describe Chore::CLI do
  it 'should allow configuration options to be registered externally' do
    args = ['some','args']
    Chore::CLI.register_option('option_name',*args)
    Chore::CLI.instance.registered_opts['option_name'].should == {:args => args}
  end

  it 'should allow configuration options to come from a file' do
    file = StringIO.new("--key-name=some_value")
    File.stub(:readlines).and_return(file.readlines)

    args = ['-k', '--key-name SOME_VALUE', "Some description"]
    cli = Chore::CLI.instance
    cli.register_option "key_name", *args
    cli.parse_config_file(file)
    cli.registered_opts['key_name'].should == {:args => args}
  end
end
