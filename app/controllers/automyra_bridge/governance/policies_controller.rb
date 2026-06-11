module AutomyraBridge
  module Governance
    class PoliciesController < BaseController
      before_action :find_policy, only: %i[show edit update destroy run_now toggle_enabled]

      def index
        @policies = policy_scope.order(:name)
      end

      def show
        @runs = @policy.governance_runs.order(created_at: :desc).limit(20)
        @findings = @policy.governance_findings.order(created_at: :desc).limit(20)
        @actions = @policy.governance_actions.order(created_at: :desc).limit(20)
      end

      def new
        @policy = ::AutomyraBridge::GovernancePolicy.new(mode: 'report_only', provider_model: 'manifest/auto', enabled: true, max_changes_per_run: 10, confidence_threshold: 0.8)
        @policy.scope_type = @project ? 'project' : 'global'
        @policy.project = @project
      end

      def create
        @policy = ::AutomyraBridge::GovernancePolicy.new(policy_params)
        @policy.scope_type = @project ? 'project' : (@policy.scope_type.presence || 'global')
        @policy.project ||= @project if @policy.project_scope?
        @policy.created_by = User.current
        if @policy.project_scope? && project_read_only?(@policy.project)
          flash.now[:error] = 'This project is read-only for Automyra. Governance policies cannot be changed.'
          render :new, status: :forbidden
        elsif @policy.save
          redirect_to automyra_bridge_governance_policy_path(@policy), notice: 'Governance policy created.'
        else
          render :new
        end
      end

      def edit; end

      def update
        if @policy.project_scope? && project_read_only?(@policy.project)
          flash.now[:error] = 'This project is read-only for Automyra. Governance policies cannot be changed.'
          render :edit, status: :forbidden
        elsif @policy.update(policy_params)
          redirect_to automyra_bridge_governance_policy_path(@policy), notice: 'Governance policy updated.'
        else
          render :edit
        end
      end

      def destroy
        if @policy.project_scope? && project_read_only?(@policy.project)
          redirect_to automyra_bridge_governance_policy_path(@policy), flash: { error: 'This project is read-only for Automyra. Governance policies cannot be deleted.' }
        else
          @policy.destroy
          redirect_to automyra_bridge_governance_policies_path(project_id: @project&.id), notice: 'Governance policy deleted.'
        end
      end

      def run_now
        mode = params[:mode].presence || @policy.mode
        unless ::AutomyraBridge::GovernancePolicy::MODES.include?(mode)
          redirect_to automyra_bridge_governance_policy_path(@policy), flash: { error: 'Choose a valid governance run mode.' }
          return
        end
        if @policy.project_scope? && project_read_only?(@policy.project) && mode == 'apply_after_validation'
          redirect_to automyra_bridge_governance_policy_path(@policy), flash: { error: 'Read-only projects cannot run governance in apply mode.' }
          return
        end

        max_changes = params[:max_changes_per_run].to_i
        if mode == 'apply_after_validation' && max_changes <= 0
          redirect_to automyra_bridge_governance_policy_path(@policy), flash: { error: 'Apply mode requires a positive max-change guardrail.' }
          return
        end
        @policy.update!(max_changes_per_run: max_changes) if max_changes.positive? && max_changes != @policy.max_changes_per_run.to_i
        ::AutomyraBridge::GovernanceRunJob.perform_later(@policy.id, mode)
        redirect_to automyra_bridge_governance_policy_path(@policy), notice: "Governance run queued in #{mode} mode."
      end

      def toggle_enabled
        if @policy.project_scope? && project_read_only?(@policy.project)
          redirect_to automyra_bridge_governance_policies_path(project_id: @project&.id), flash: { error: 'This project is read-only for Automyra. Governance policies cannot be changed.' }
          return
        end

        @policy.update!(enabled: !@policy.enabled)
        action = @policy.enabled? ? 'enabled' : 'paused'
        redirect_to automyra_bridge_governance_policies_path(project_id: @project&.id), notice: "Governance policy #{@policy.name} has been #{action}."
      end

      def run_all_now
        queued = 0
        skipped = 0
        policy_scope.find_each do |policy|
          if policy.enabled? && !(policy.project_scope? && project_read_only?(policy.project) && policy.mode == 'apply_after_validation')
            ::AutomyraBridge::GovernanceRunJob.perform_later(policy.id, policy.mode)
            queued += 1
          else
            skipped += 1
          end
        end

        message = "Queued #{queued} governance #{'run'.pluralize(queued)}."
        message += " Skipped #{skipped}." if skipped.positive?
        redirect_to automyra_bridge_governance_policies_path(project_id: @project&.id), notice: message
      end

      private

      def find_policy
        @policy = policy_scope.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_404
      end

      def policy_params
        params.require(:automyra_bridge_governance_policy).permit(:name, :project_id, :scope_type, :policy_page_id, :config, :mode, :provider_model, :max_changes_per_run, :confidence_threshold, :frequency_hours, :enabled, :scope_wiki_pages, :scope_tasks, :scope_attachments, :scope_requirement_links, :scope_wiki_requirement_links, :scope_task_requirement_links, :exclusions)
      end

      def project_read_only?(project)
        project && ::AutomyraBridgeProjectSetting.for_project(project).read_only?
      end
    end
  end
end
