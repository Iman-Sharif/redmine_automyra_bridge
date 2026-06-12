module AutomyraBridge
  module Tools
    class IssueSetPriorityTool < BaseTool
      include ResolvesTarget

      NAME = 'issue.set_priority'.freeze
      LEGACY_ACTION_TYPE = 'set_issue_priority'.freeze
      DESCRIPTION = 'Set priority on the current issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['issue'], properties: { issue: { type: 'object', required: ['priority_id'], properties: { priority_id: { type: 'integer' } } } } }.freeze

      self.target_resolver = :source_issue
      self.target_name = 'Issue'
      self.target_id_key = :issue_id

      def required_permission
        :edit_issues
      end

      def call(job, _user, input)
        issue = resolve_target!(job)
        priority_id = input.dig('issue', 'priority_id') || input['priority_id']
        raise 'Issue priority is not available.' unless IssuePriority.find_by(id: priority_id)

        issue.update!(priority_id: priority_id)
        { issue_id: issue.id, priority_id: issue.priority_id }
      end

      def verify!(result, input)
        priority_id = input.dig('issue', 'priority_id') || input['priority_id']
        raise 'Issue priority verification failed.' unless Issue.find_by(id: result[:issue_id])&.priority_id.to_i == priority_id.to_i
      end
    end
  end
end
