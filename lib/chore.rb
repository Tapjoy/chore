module Chore
  VERSION = '0.0.1'

  autoload :Job,            'chore/job'
  autoload :Worker,         'chore/worker'

  autoload :JsonEncoder,    'chore/json_encoder'
  autoload :Publisher,      'chore/publisher'

  # Helpers and convenience modules
  autoload :Hooks,          'chore/hooks'
  autoload :Util,           'chore/util'
 
end
