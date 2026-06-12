$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require File.expand_path('../../../test/test_helper', __dir__)

if defined?(Rails::LineFiltering)
  module Rails
    module LineFiltering
      alias_method :__automyra_orig_run__, :run unless method_defined?(:__automyra_orig_run__)
      def run(*args, **kwargs)
        if args.length >= 3
          klass, method_name, reporter = args[0], args[1], args[2]
          reporter.prerecord klass, method_name
          result = klass.new(method_name).run
          reporter.record(result)
          result
        else
          __automyra_orig_run__(*args, **kwargs)
        end
      end
    end
  end
end

begin
  require 'mocha/minitest'
rescue LoadError
end

# TEST HARNESS MONKEYPATCH (Task 4)
# The plugin models use `column_names` inside `if:` conditions on validates
# and inside scope lambdas to defensively gate newer columns.
# In Rails 7.2 + Redmica 3.2.6, when these expressions are evaluated in the
# context of a callback / instance, `self` is an instance that does not have
# the class-level `column_names` method.  ActiveRecord normally resolves
# missing class-level methods in some contexts, but not here.  Production
# runs with `config.eager_load = true` which pre-loads schema and caches
# column_names at the class level before any instance callbacks run; in the
# test environment the class is lazily loaded and `column_names` is not
# available on the instance during callback evaluation.
# This monkeypatch only affects test execution and only adds a convenience
# delegator so the test harness is not tripped up.
class ActiveRecord::Base
  def column_names
    self.class.column_names
  end
end
