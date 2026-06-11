module AutomyraBridge
  module Governance
    module Executors
      ApplyResult = Struct.new(:status, :message, :action, keyword_init: true) do
        def applied?
          status.to_s == 'applied'
        end

        def failed?
          status.to_s == 'failed'
        end

        def skipped?
          status.to_s == 'skipped'
        end
      end
    end
  end
end
