module AutomyraBridge
  module Governance
    class ActionsController < BaseController
      def index
        @actions = ::AutomyraBridge::GovernanceAction.where(governance_policy_id: policy_scope.select(:id))
        @actions = @actions.where(governance_policy_id: params[:policy_id]) if params[:policy_id].present?
        @actions = @actions.where(governance_finding_id: params[:finding_id]) if params[:finding_id].present?
        @actions = @actions.where(status: params[:status]) if params[:status].present?
        @actions = @actions.where(action_type: params[:action_type]) if params[:action_type].present?
        @actions = @actions.order(created_at: :desc).limit(100)
      end

      def show
        @action = ::AutomyraBridge::GovernanceAction.includes(:governance_policy, :governance_run, :governance_finding, :created_by).find(params[:id])
      end
    end
  end
end
