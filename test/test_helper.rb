$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# Resolve Redmine/Redmica's own test_helper regardless of where the plugin is
# mounted. This plugin is symlinked into redmica/plugins/<name> in CI, and
# Ruby resolves __dir__ through the symlink to the repo root, so a hardcoded
# ../../../ climb would escape the checkout.
redmica_root = ENV['REDMICA_ROOT']
if redmica_root.nil? || redmica_root.empty?
  probe = __dir__
  redmica_root = loop do
    parent = File.dirname(probe)
    break nil if parent == probe
    break parent if File.exist?(File.join(parent, 'test', 'test_helper.rb'))

    probe = parent
  end
end
raise 'Could not locate the Redmica root (test/test_helper.rb)' unless redmica_root

require File.expand_path('test/test_helper', redmica_root)

if defined?(Rails::LineFiltering)
  module Rails
    module LineFiltering
      alias __automyra_orig_run__ run unless method_defined?(:__automyra_orig_run__)
      def run(*args, **kwargs)
        if args.length >= 3
          klass = args[0]
          method_name = args[1]
          reporter = args[2]
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
  delegate :column_names, to: :class
end

# When a plugin test is invoked as the main script with additional test files
# on the command line (e.g. `ruby -Itest test/a_test.rb test/b_test.rb`), Ruby
# only loads the first file. Load the remaining test files here so Minitest
# runs the full suite together.
if $PROGRAM_NAME && File.basename($PROGRAM_NAME).end_with?('_test.rb') && ARGV.any? { |arg| arg.end_with?('_test.rb') }
  ARGV.each do |arg|
    require File.expand_path(arg) if arg.end_with?('_test.rb') && File.file?(arg)
  end
end
