module AutomyraBridge
  module Governance
    class BaseController < ApplicationController
      before_action :require_login
      before_action :find_project
      before_action :authorize_governance!

      helper AutomyraBridge::GovernanceHelper
      helper_method :governance_project, :governance_read_only?

      private

      def find_project
        @project = if params[:project_id].present?
                     Project.find(params[:project_id])
                   elsif params[:policy_id].present?
                     ::AutomyraBridge::GovernancePolicy.find(params[:policy_id]).project
                    elsif params[:id].present? && controller_name == 'policies'
                      ::AutomyraBridge::GovernancePolicy.find(params[:id]).project
                    elsif controller_name == 'policies'
                      nil
                    elsif User.current.admin?
                      nil
                   else
                     Project.visible.detect { |project| User.current.allowed_to?(:manage_automyra_bridge, project) }
                   end
        render_404 unless @project || supports_global_governance?
      rescue ActiveRecord::RecordNotFound
        render_404
      end

      def authorize_governance!
        return if User.current.admin?
        return if @project && User.current.allowed_to?(:manage_automyra_bridge, @project)
        return if controller_name == 'policies' && manageable_projects.any?

        render_403
      end

      def governance_project
        @project
      end

      def governance_read_only?
        @project && ::AutomyraBridgeProjectSetting.for_project(@project).read_only?
      end

      def policy_scope
        if @project
          ::AutomyraBridge::GovernancePolicy.where(project: @project).or(::AutomyraBridge::GovernancePolicy.where(scope_type: 'global'))
        else
          ::AutomyraBridge::GovernancePolicy.where(scope_type: 'global').or(::AutomyraBridge::GovernancePolicy.where(project_id: manageable_projects.map(&:id)))
        end
      end

      def manageable_projects
        return Project.where(status: Project::STATUS_ACTIVE) if User.current.admin?

        Project.visible.where(status: Project::STATUS_ACTIVE).select { |project| User.current.allowed_to?(:manage_automyra_bridge, project) }
      end

      def set_governance_action_menu
        @governance_menu = true
      end

      def supports_global_governance?
        %w[policies runs findings actions].include?(controller_name)
      end
    end
  end
end
