module AutomyraBridge
  module Tools
    class IssueSetDueDateTool < BaseTool
      NAME = 'issue.set_due_date'.freeze
      LEGACY_ACTION_TYPE = 'set_issue_due_date'.freeze
      DESCRIPTION = 'Set due date on the current issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['issue'], properties: { issue: { type: 'object', required: ['due_date'], properties: { due_date: { type: 'string' } } } } }.freeze

      def required_permission
        :edit_issues
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, _user, input)
        issue = source_issue(job) || raise('Issue is no longer available.')
        due_date = input.dig('issue', 'due_date') || input['due_date']
        issue.update!(due_date: due_date)
        { issue_id: issue.id, due_date: issue.due_date&.to_s }
      end
    end
  end
end
