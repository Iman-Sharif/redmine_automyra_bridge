module AutomyraBridge
  module Governance
    class FindingsController < BaseController
      def index
        @findings = ::AutomyraBridge::GovernanceFinding.where(governance_policy_id: policy_scope.select(:id))
        @findings = @findings.where(governance_policy_id: params[:policy_id]) if params[:policy_id].present?
        @findings = @findings.where(object_type: params[:object_type]) if params[:object_type].present?
        @findings = @findings.where(status: params[:status]) if params[:status].present?
        @findings = @findings.where(finding_type: params[:finding_type]) if params[:finding_type].present?
        @findings = @findings.where('confidence >= ?', params[:minimum_confidence].to_d) if params[:minimum_confidence].present?
        @findings = @findings.order(created_at: :desc).limit(100)
      end

      def show
        @finding = ::AutomyraBridge::GovernanceFinding.find(params[:id])
      end
    end
  end
end
