module AutomyraBridge
  module Tools
    class IssueUpdateTool < BaseTool
      NAME = 'issue.update'.freeze
      LEGACY_ACTION_TYPE = 'update_issue'.freeze
      DESCRIPTION = 'Update fields on the current issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['issue'], properties: { issue: { type: 'object' } } }.freeze

      def required_permission
        :edit_issues
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, _user, input)
        issue = source_issue(job) || raise('Issue is no longer available.')
        attrs = issue_attributes(input['issue'] || input)
        raise 'No issue fields supplied.' if attrs.empty?
        issue.update!(attrs)
        { issue_id: issue.id }
      end
    end
  end
end
