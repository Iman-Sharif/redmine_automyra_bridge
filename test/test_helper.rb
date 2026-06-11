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
