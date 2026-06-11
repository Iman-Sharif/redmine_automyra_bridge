module AutomyraBridge
  module Governance
    class RunsController < BaseController
      def index
        @runs = ::AutomyraBridge::GovernanceRun.where(governance_policy_id: policy_scope.select(:id)).order(created_at: :desc).limit(100)
      end

      def show
        @run = ::AutomyraBridge::GovernanceRun.where(governance_policy_id: policy_scope.select(:id)).find(params[:id])
        @findings = @run.governance_findings.order(created_at: :desc)
        @actions = @run.governance_actions.order(created_at: :desc)
      rescue ActiveRecord::RecordNotFound
        render_404
      end
    end
  end
end
