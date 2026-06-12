module AutomyraBridge
  module Tools
    class IssueAddCommentTool < BaseTool
      include ResolvesTarget

      NAME = 'issue.add_comment'.freeze
      LEGACY_ACTION_TYPE = 'add_issue_comment'.freeze
      DESCRIPTION = 'Add a journal comment to the current issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['comment'], properties: { comment: { type: 'object', required: ['body'], properties: { body: { type: 'string' } } } } }.freeze

      self.target_resolver = :source_issue
      self.target_name = 'Issue'
      self.target_id_key = :issue_id

      def required_permission
        :add_issue_notes
      end

      def call(job, user, input)
        # PINNED DIVERGENCE (Task 7): issue.add_comment returns body String under :comment
        issue = resolve_target!(job)

        body = input.dig('comment', 'body').to_s.strip
        raise 'Comment body is blank.' if body.blank?

        issue.init_journal(user, body)
        raise issue.errors.full_messages.join(', ') unless issue.save

        { issue_id: issue.id, comment: body }
      end

      def verify!(result, input)
        issue = Issue.find_by(id: result[:issue_id])
        raise 'Issue comment verification failed.' unless issue

        body = input.dig('comment', 'body').to_s.strip
        journal = issue.journals.order(id: :desc).first
        raise 'Issue comment verification failed.' unless journal&.notes == body
      end
    end
  end
end
