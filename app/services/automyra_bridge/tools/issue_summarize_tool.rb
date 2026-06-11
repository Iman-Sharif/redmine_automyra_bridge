module AutomyraBridge
  module Tools
    class IssueSummarizeTool < BaseTool
      NAME = 'issue.summarize'.freeze
      LEGACY_ACTION_TYPE = 'summarize_issue'.freeze
      DESCRIPTION = 'Summarize the current issue and recent journals.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {} }.freeze

      def required_permission
        :view_issues
      end

      def available?(job)
        source_issue(job).present?
      end

      def call(job, _user, _input)
        issue = source_issue(job) || raise('Issue is no longer available.')
        notes = issue.journals.order(:created_on).last(5).map(&:notes).reject(&:blank?)
        { issue_id: issue.id, summary: ([issue.subject, issue.description.presence].compact + notes).join("\n\n").truncate(1000) }
      end
    end
  end
end
