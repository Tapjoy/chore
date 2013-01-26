module Chore
  module Hooks

    def run_hooks_for(event,*args)
      results = hooks_for(event).map { |method| send(method,*args) } || true
      results = false if results.any? {|r| false == r }
      results
    end

  private
    def hooks_for(event)
      (self.methods - Object.methods).grep(/^#{event}/).sort
    end
  end
end
