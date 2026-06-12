module AutomyraBridge
  module Tools
    class IssueCreateTool < BaseTool
      NAME = 'issue.create'.freeze
      LEGACY_ACTION_TYPE = 'create_issue'.freeze
      DESCRIPTION = 'Create an issue in the current project.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['issue'], properties: { issue: { type: 'object', required: ['subject'], properties: { subject: { type: 'string' }, description: { type: 'string' }, tracker_id: { type: 'integer' }, assigned_to_id: { type: 'integer' }, priority_id: { type: 'integer' }, due_date: { type: 'string' } } } } }.freeze

      def required_permission
        :add_issues
      end

      def call(job, user, input)
        attrs = issue_attributes(input['issue'] || input)
        issue = Issue.new(attrs.merge(project_id: job.project_id, author_id: user.id))
        issue.tracker ||= job.project.trackers.first || Tracker.first
        issue.status ||= IssueStatus.sorted.first
        issue.priority ||= IssuePriority.default || IssuePriority.first
        issue.save!
        { issue_id: issue.id }
      end

      def verify!(result, input)
        issue = Issue.find_by(id: result[:issue_id])
        raise 'Issue create verification failed.' unless issue

        subject = (input['issue'] || input)['subject'].to_s
        raise 'Issue subject verification failed.' unless issue.subject == subject
      end
    end
  end
end
