module AutomyraBridge
  module Tools
    class IssueAssignTool < BaseTool
      include ResolvesTarget

      NAME = 'issue.assign'.freeze
      LEGACY_ACTION_TYPE = 'assign_issue'.freeze
      DESCRIPTION = 'Assign the current issue to a user.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['assignment'], properties: { assignment: { type: 'object', required: ['assigned_to_id'], properties: { assigned_to_id: { type: 'integer' } } } } }.freeze

      self.target_resolver = :source_issue
      self.target_name = 'Issue'
      self.target_id_key = :issue_id

      def required_permission
        :edit_issues
      end

      def call(job, _user, input)
        issue = resolve_target!(job)
        assigned_to_id = input.dig('assignment', 'assigned_to_id') || input['assigned_to_id']
        raise 'Assigned user is not available.' unless User.active.find_by(id: assigned_to_id)

        issue.update!(assigned_to_id: assigned_to_id)
        { issue_id: issue.id, assigned_to_id: issue.assigned_to_id }
      end
    end
  end
end
