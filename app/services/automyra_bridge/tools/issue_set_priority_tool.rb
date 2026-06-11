module AutomyraBridge
  module Tools
    class IssueSetPriorityTool < BaseTool
      NAME = 'issue.set_priority'.freeze
      LEGACY_ACTION_TYPE = 'set_issue_priority'.freeze
      DESCRIPTION = 'Set priority on the current issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['issue'], properties: { issue: { type: 'object', required: ['priority_id'], properties: { priority_id: { type: 'integer' } } } } }.freeze

      def required_permission
        :edit_issues
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, _user, input)
        issue = source_issue(job) || raise('Issue is no longer available.')
        priority_id = input.dig('issue', 'priority_id') || input['priority_id']
        raise 'Issue priority is not available.' unless IssuePriority.find_by(id: priority_id)
        issue.update!(priority_id: priority_id)
        { issue_id: issue.id, priority_id: issue.priority_id }
      end
    end
  end
end
