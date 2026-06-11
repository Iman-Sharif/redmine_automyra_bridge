module AutomyraBridge
  module Tools
    class IssueAssignToRequesterTool < BaseTool
      NAME = 'issue.assign_to_requester'.freeze
      LEGACY_ACTION_TYPE = 'assign_issue_to_requester'.freeze
      DESCRIPTION = 'Assign the current issue to the requesting user.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { issue_id: { type: 'integer' } } }.freeze

      def required_permission
        :edit_issues
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, user, _input)
        issue = source_issue(job)
        raise 'Issue is no longer available.' unless issue

        issue.assigned_to = user
        issue.init_journal(user, 'Assigned by Automyra at the requester’s instruction.')
        raise issue.errors.full_messages.join(', ') unless issue.save

        { issue_id: issue.id, assigned_to_id: user.id }
      end

      def verify!(result, _input)
        issue = Issue.find_by(id: result[:issue_id])
        raise 'Issue assignment verification failed.' unless issue&.assigned_to_id.to_s == result[:assigned_to_id].to_s
      end
    end
  end
end
