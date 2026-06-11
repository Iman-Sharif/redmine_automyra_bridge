module AutomyraBridge
  module Tools
    class IssueSetStatusTool < BaseTool
      NAME = 'issue.set_status'.freeze
      LEGACY_ACTION_TYPE = 'set_issue_status'.freeze
      DESCRIPTION = 'Set status on the current issue.'.freeze
      RISK_LEVEL = 'destructive_soft'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['issue'], properties: { issue: { type: 'object', required: ['status_id'], properties: { status_id: { type: 'integer' } } } } }.freeze

      def required_permission
        :edit_issues
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, _user, input)
        issue = source_issue(job) || raise('Issue is no longer available.')
        status_id = input.dig('issue', 'status_id') || input['status_id']
        new_status = IssueStatus.find_by(id: status_id)
        raise 'Issue status is not available.' unless new_status

        # Workflow-safe transition check
        allowed_statuses = issue.new_statuses_allowed_to(User.current, false)
        unless allowed_statuses.include?(new_status) || issue.status_id == new_status.id
          raise "Status transition from #{issue.status} to #{new_status} is not allowed by the workflow."
        end

        issue.init_journal(User.current)
        issue.status = new_status
        issue.save!
        { issue_id: issue.id, status_id: issue.status_id }
      end
    end
  end
end
