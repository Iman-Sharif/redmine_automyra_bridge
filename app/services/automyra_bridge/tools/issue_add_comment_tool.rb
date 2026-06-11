module AutomyraBridge
  module Tools
    class IssueAddCommentTool < BaseTool
      NAME = 'issue.add_comment'.freeze
      LEGACY_ACTION_TYPE = 'add_issue_comment'.freeze
      DESCRIPTION = 'Add a journal comment to the current issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['comment'], properties: { comment: { type: 'object', required: ['body'], properties: { body: { type: 'string' } } } } }.freeze

      def required_permission
        :add_issue_notes
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, user, input)
        issue = source_issue(job)
        raise 'Issue is no longer available.' unless issue

        body = input.dig('comment', 'body').to_s.strip
        raise 'Comment body is blank.' if body.blank?

        issue.init_journal(user, body)
        raise issue.errors.full_messages.join(', ') unless issue.save

        { issue_id: issue.id, comment: body }
      end
    end
  end
end
