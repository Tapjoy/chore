module Chore

  # Collection of utilities and helpers used by Chore internally
  module Util

    # To avoid bringing in all of active_support, we implemented constantize here
    def constantize(camel_cased_word)
      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end

    def procline(str)
      $0 = str
    end
  end
end
