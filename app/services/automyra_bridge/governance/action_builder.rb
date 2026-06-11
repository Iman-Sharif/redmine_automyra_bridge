require 'digest'

module AutomyraBridge
  module Governance
    class ActionBuilder
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(run:, policy: nil, findings:, created_by: nil)
        @run = run
        @policy = policy || run.governance_policy
        @findings = Array(findings)
        @created_by = created_by || run.created_by
      end

      def call
        AutomyraBridge::GovernanceAction.transaction do
          actions = @findings.filter_map { |finding| build_action(finding) }
          @run.update!(actions_count: @run.governance_actions.count)
          actions
        end
      end

      def self.idempotency_key(policy:, object_type:, object_id:, action_type:, current_value:, recommended_value:)
        [
          policy.id,
          object_type,
          object_id,
          action_type,
          Digest::SHA256.hexdigest(current_value.to_s),
          Digest::SHA256.hexdigest(recommended_value.to_s)
        ].join(':')
      end

      private

      def build_action(finding)
        return unless finding.status == 'valid'

        action_type = action_type_for(finding)
        key = self.class.idempotency_key(
          policy: @policy,
          object_type: finding.object_type,
          object_id: finding.object_id,
          action_type: action_type,
          current_value: finding.current_value,
          recommended_value: finding.recommended_value
        )

        action = AutomyraBridge::GovernanceAction.find_or_create_by!(idempotency_key: key) do |record|
          record.governance_run = @run
          record.governance_finding = finding
          record.governance_policy = @policy
          record.action_type = action_type
          record.object_type = finding.object_type
          record.object_id = finding.object_id
          record.rollback_payload = rollback_payload(finding).to_json
          record.before_value = finding.current_value
          record.after_value = finding.recommended_value
          record.status = 'validated'
          record.created_by = @created_by
        end
        action.mark_validated! if action.pending?
        action
      end

      def action_type_for(finding)
        case finding.finding_type
        when 'wiki_title' then 'update_wiki_title'
        when 'task_title' then 'update_task_title'
        when 'attachment_filename' then attachment_filename_action_type
        when 'wiki_summary' then 'review_wiki_summary'
        when 'wiki_metadata' then 'review_wiki_metadata'
        when 'wiki_heading_structure' then 'review_wiki_heading_structure'
        when 'wiki_requirement_link' then 'link_wiki_requirement'
        when 'task_requirement_link' then 'link_task_requirement'
        else 'propose'
        end
      end

      def rollback_payload(finding)
        if finding.finding_type.to_s.include?('title')
          { title: finding.current_value }
        elsif finding.finding_type == 'attachment_filename'
          { filename: finding.current_value, attachment_id: finding.object_id }
        elsif %w[wiki_summary wiki_metadata wiki_heading_structure].include?(finding.finding_type)
          { content: finding.current_value }
        else
          { existing_relation_ids: [] }
        end
      end

      def attachment_filename_action_type
        @policy.mode.to_s == 'apply_after_validation' ? 'update_attachment_filename' : 'review_attachment_filename'
      end
    end
  end
end
