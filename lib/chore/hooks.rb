module Chore
  module Hooks

    # 
    # Helper method to look up, and execute hooks based on an event name.
    # Hooks are assumed to be methods defined on `self` that are of the pattern
    # hook_name_identifier. ex: before_perform_log
    #
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
