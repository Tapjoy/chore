module Chore
  class Railtie < Rails::Railtie
    rake_tasks do
      Dir[File.join(File.dirname(__FILE__),'tasks/*.task')].each { |f| load f }
    end

    config.after_initialize do
      if Chore.configuring?
        # Reset the logger on forks to avoid deadlocks
        Rails.logger = Chore.logger
        Chore.add_hook(:after_fork) do |worker|
          Rails.logger = Chore.logger
        end
      end
    end
  end
end