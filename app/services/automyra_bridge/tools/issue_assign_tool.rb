module AutomyraBridge
  module Tools
    class IssueAssignTool < BaseTool
      NAME = 'issue.assign'.freeze
      LEGACY_ACTION_TYPE = 'assign_issue'.freeze
      DESCRIPTION = 'Assign the current issue to a user.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['assignment'], properties: { assignment: { type: 'object', required: ['assigned_to_id'], properties: { assigned_to_id: { type: 'integer' } } } } }.freeze

      def required_permission
        :edit_issues
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, _user, input)
        issue = source_issue(job) || raise('Issue is no longer available.')
        assigned_to_id = input.dig('assignment', 'assigned_to_id') || input['assigned_to_id']
        raise 'Assigned user is not available.' unless User.active.find_by(id: assigned_to_id)

        issue.update!(assigned_to_id: assigned_to_id)
        { issue_id: issue.id, assigned_to_id: issue.assigned_to_id }
      end
    end
  end
end
