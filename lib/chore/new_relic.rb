require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  @name = :chore

  ## The intention here is not to load this if we're on the publishing side of Chore, only consuming.
  depends_on do
    defined?(::Chore::CLI) && !NewRelic::Agent.config[:disable_chore]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing NewRelic instrumentation'
  end

  executes do

    module Chore
      module NewRelicInstrumentation
        ## Override perform to add NewRelic tracing. Call the super perform todo the actual work
        include NewRelic::Agent::Instrumentation::ControllerInstrumentation

        def perform(*args)
          Chore.logger.debug "Logging #{self.name}#perform to NewRelic"
          perform_action_with_newrelic_trace(:name => 'perform',
                               :class_name => self.name,
                               :category => 'OtherTransaction/ChoreJob') do
            super(*args)
          end
        end
      end
    end

    module NewRelic
      module Agent
        module Instrumentation
          module ChoreInstrumentHook
            ## Override `payload_class` to take the new job class instance, and extend the above instrumentation
            ## into it. This makes sure we're only messing with classes that are actually being processed.
            def payload_class(message)
              klass = super
              klass.instance_eval do
                extend ::Chore::NewRelicInstrumentation
              end
              klass
            end
          end
        end
      end
    end

    ## A bit naughty, but override the constructor on `Chore::Worker` to inject the `payload_class` override into
    ## each newly constructed worker. The advantage to this over slightly more dynamic methods is that module injection
    ## gives us a class heirarchy so we get access to `super` in the hooked methods.
    ::Chore::Worker.class_eval do
      def self.new(*args)
        super(*args).extend NewRelic::Agent::Instrumentation::ChoreInstrumentHook
      end
    end

    ## TODO: Make this smart enough to work with non-forking workers. Right now it assumes a forking worker
    ##      because that's the only one we have. But it just plain won't work with non-forking workers.
    if NewRelic::LanguageSupport.can_fork?
      ## Start the NewRelic agent in the parent process so we only have one agent thread sending data.
      ::Chore.add_hook(:before_first_fork) do
        NewRelic::Agent.manual_start(:dispatcher   => :resque, # We look close enough to resque for this to work
                                     :sync_startup => true,
                                     :start_channel_listener => true, # This lets us control which workers report where.
                                                                      # We could get fancy, but we won't really need it.
                                     :report_instance_busy => false)  # No idea, honestly, but the docs recommend it.
      end

      ## In the parent, setup a report channel (pipe) tied to this worker's id. Since we have the worker before we fork
      ## it's `object_id` will be the same in the child. So it's a convenient unique id for parent/child to share.
      ## The `pid` would seem to be obvious, but is slightly less trivial to access on the parent end, at the right time.
      ::Chore.add_hook(:before_fork) do |worker|
        NewRelic::Agent.register_report_channel(worker.object_id)
      end

      ::Chore.add_hook(:after_fork) do |worker|
        NewRelic::Agent.after_fork(:report_to_channel => worker.object_id)
      end

      ## Before Chore shuts itself down, tell NewRelic to do the same.
      ::Chore.add_hook(:before_shutdown) do
        NewRelic::Agent.shutdown if NewRelic::LanguageSupport.can_fork?
      end
    end
  end
end

# call this now so it is memoized before potentially forking worker processes
NewRelic::LanguageSupport.can_fork?
