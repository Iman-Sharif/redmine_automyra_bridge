require 'securerandom'

module AutomyraBridge
  module Governance
    class ProposalIntegrator
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(run:, actions:, created_by: nil)
        @run = run
        @policy = run.governance_policy
        @actions = Array(actions)
        @created_by = created_by || run.created_by || @policy.created_by
      end

      def call
        AutomyraBridgeActionProposal.transaction do
          @actions.map { |action| integrate_action(action) }
        end
      end

      private

      def integrate_action(action)
        proposal = AutomyraBridgeActionProposal.find_or_create_by!(idempotency_key: proposal_idempotency_key(action)) do |record|
          record.automyra_bridge_job = governance_job(action)
          record.project = @policy.project
          record.task = task_for(action)
          record.user = @created_by
          record.action_type = proposal_action_type(action)
          record.status = 'pending'
          record.request_payload = proposal_payload(action).to_json
        end
        action.mark_proposed! unless action.proposed?
        proposal
      end

      def governance_job(action)
        AutomyraBridgeJob.find_or_create_by!(source_type: 'AutomyraBridge::GovernanceAction', source_id: action.id) do |job|
          job.project = @policy.project
          job.user = @created_by
          job.status = 'succeeded'
          job.correlation_id = SecureRandom.uuid
          job.idempotency_key = "governance-action-#{action.id}-#{SecureRandom.uuid}"
          job.request_payload = { source: 'governance_action', governance_action_id: action.id, governance_run_id: @run.id }.to_json
        end
      end

      def proposal_action_type(action)
        case action.action_type
        when 'update_task_title' then 'update_task'
        when 'update_wiki_title' then 'update_wiki'
        when 'link_task_requirement' then 'link_task_issue'
        when 'link_wiki_requirement' then 'update_wiki'
        else 'unsupported_action'
        end
      end

      def proposal_payload(action)
        finding = action.governance_finding
        {
          action_type: proposal_action_type(action),
          idempotency_key: proposal_idempotency_key(action),
          governance: {
            governance_action_id: action.id,
            governance_finding_id: finding.id,
            governance_run_id: @run.id,
            governance_policy_id: @policy.id,
            action_type: action.action_type,
            rollback_payload: parse_json(action.rollback_payload)
          },
          target: { type: action.object_type, id: action.object_id },
          task: task_payload(action, finding),
          wiki: wiki_payload(action, finding),
          current_value: finding.current_value,
          recommended_value: finding.recommended_value,
          rationale: finding.rationale
        }.compact
      end

      def task_payload(action, finding)
        return unless action.action_type == 'update_task_title'

        { id: action.object_id, title: finding.recommended_value }
      end

      def wiki_payload(action, finding)
        return unless %w[update_wiki_title link_wiki_requirement].include?(action.action_type)

        { id: action.object_id, title: finding.recommended_value, governance_update: true }
      end

      def task_for(action)
        return unless action.object_type == 'TaskHub::Task' && defined?(TaskHub::Task)

        TaskHub::Task.find_by(id: action.object_id)
      end

      def proposal_idempotency_key(action)
        "#{action.idempotency_key}:proposal"
      end

      def parse_json(raw)
        JSON.parse(raw.to_s.presence || '{}')
      rescue JSON::ParserError
        {}
      end
    end
  end
end
