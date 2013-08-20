module Chore
  class Railtie < Rails::Railtie
    rake_tasks do
      Dir[File.join(File.dirname(__FILE__),'tasks/*.task')].each { |f| load f }
    end
  end
end
