module AutomyraBridge
  module Governance
    module Executors
      class BaseExecutor
        def self.call(action)
          new(action).call
        end

        def initialize(action)
          @action = action
          @finding = action.governance_finding
          @policy = action.governance_policy
          @actor = action.created_by || action.governance_run.created_by || @policy.created_by || User.current
        end

        def call
          action.mark_validated! unless action.applied?
          ApplyResult.new(status: 'skipped', message: 'review action requires manual review', action: action)
        end

        private

        attr_reader :action, :finding, :policy, :actor

        def fail_action!(message)
          action.mark_failed!
          finding.mark_invalid!(evaluator_error: message) unless finding.applied?
          ApplyResult.new(status: 'failed', message: message, action: action)
        end

        def apply_success!(rollback_payload)
          action.mark_applied!(rollback_payload: rollback_payload.to_json)
          finding.mark_applied!
          ApplyResult.new(status: 'applied', message: 'applied', action: action)
        end

        def ensure_permission!(permission, project)
          return true if actor&.admin? || actor&.allowed_to?(permission, project)

          raise 'Governance action is not permitted.'
        end

        def ensure_current_value!(current_value)
          return true if current_value.to_s == finding.current_value.to_s

          raise 'Governance target changed since validation.'
        end

        def requirement_issue
          issue_id = finding.recommended_value.to_s[/\d+/]
          Issue.find_by(id: issue_id)
        end
      end
    end
  end
end
