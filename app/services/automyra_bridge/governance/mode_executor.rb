module AutomyraBridge
  module Governance
    class ModeExecutor
      Result = Struct.new(:findings, :actions, :proposals, :applied_count, keyword_init: true)

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(run:, policy: nil, findings:, config: nil, created_by: nil)
        @run = run
        @policy = policy || run.governance_policy
        @findings = Array(findings)
        @config = (config || PolicyLoader.normalize_policy_config(@policy)).deep_stringify_keys
        @created_by = created_by || run.created_by || @policy.created_by
      end

      def call
        AutomyraBridge::GovernanceRun.transaction do
          persisted_findings = FindingPersistor.call(run: @run, policy: @policy, findings: @findings, created_by: @created_by)
          actions = []
          proposals = []
          applied_count = 0

          if %w[propose apply_after_validation].include?(mode)
            actions = ActionBuilder.call(run: @run, policy: @policy, findings: persisted_findings, created_by: @created_by)
          end

          if mode == 'propose'
            proposals = ProposalIntegrator.call(run: @run, actions: actions, created_by: @created_by)
          elsif mode == 'apply_after_validation'
            applied_count = apply_actions(actions)
          end

          @run.update!(findings_count: @run.governance_findings.count, actions_count: @run.governance_actions.count, applied_count: applied_count)
          Result.new(findings: persisted_findings, actions: actions, proposals: proposals, applied_count: applied_count)
        end
      end

      private

      def mode
        @config['mode'].presence || @policy.mode
      end

      def apply_actions(actions)
        allowed = max_changes_per_run || actions.size
        applied = 0
        actions.first(allowed).each do |action|
          next if action.applied?
          next if read_only_action_project?(action)

          apply_action!(action)
          applied += 1 if action.reload.applied?
        end
        applied
      end

      def apply_action!(action)
        executor_for(action).call(action)
      end

      def executor_for(action)
        case action.action_type
        when 'update_task_title' then Executors::TaskTitleExecutor
        when 'update_wiki_title' then Executors::WikiTitleExecutor
        when 'link_task_requirement' then Executors::TaskRequirementLinkExecutor
        when 'link_wiki_requirement' then Executors::WikiRequirementLinkExecutor
        when 'update_attachment_filename' then Executors::AttachmentFilenameExecutor
        when 'review_attachment_filename' then Executors::BaseExecutor
        else Executors::BaseExecutor
        end
      end

      def max_changes_per_run
        value = @config['max_changes_per_run']
        value.present? ? value.to_i : nil
      end

      def read_only_action_project?(action)
        project = action_project(action)
        project && ::AutomyraBridgeProjectSetting.for_project(project).read_only?
      end

      def action_project(action)
        object = action.object_type.safe_constantize&.where(id: action.object_id)&.first
        object.respond_to?(:project) ? object.project : nil
      rescue StandardError
        nil
      end
    end
  end
end
