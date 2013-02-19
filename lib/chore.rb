module Chore
  VERSION = '0.0.1'

  autoload :Job,            'chore/job'
  autoload :Worker,         'chore/worker'

  autoload :JsonEncoder,    'chore/json_encoder'
  autoload :Publisher,      'chore/publisher'
  autoload :Manager,        'chore/manager'
  autoload :Fetcher,        'chore/fetcher'
  autoload :Consumer,       'chore/consumer'

  # Helpers and convenience modules
  autoload :Hooks,          'chore/hooks'
  autoload :Util,           'chore/util'

  class UnitOfWork < Struct.new(:id,:message,:consumer); end;
 
  def self.add_hook(name,&blk)
    @@hooks ||= {}
    (@@hooks[name.to_sym] ||= []) << blk
  end

  def self.hooks_for(name)
    @@hooks ||= {}
    @@hooks[name.to_sym] || []
  end

  def self.clear_hooks!
    @@hooks = {}
  end

  def self.run_hooks_for(name)
    hooks = self.hooks_for(name)
    hooks.each(&:call) unless hooks.nil? || hooks.empty?
  end

end
