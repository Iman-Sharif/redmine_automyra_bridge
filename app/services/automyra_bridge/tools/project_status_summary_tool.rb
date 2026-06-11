module AutomyraBridge
  module Tools
    class ProjectStatusSummaryTool < BaseTool
      NAME = 'project.status_summary'.freeze
      LEGACY_ACTION_TYPE = 'project_status_summary'.freeze
      DESCRIPTION = 'Summarize visible task and issue status counts for the current project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {} }.freeze

      def call(job, user, _input)
        tasks = defined?(TaskHub::Task) ? TaskHub::Task.where(project_id: job.project_id) : TaskHub::Task.none
        issues = Issue.visible(user).where(project_id: job.project_id)
        { tasks: tasks.group(:status).count, issues: issues.joins(:status).group('issue_statuses.name').count }
      end
    end
  end
end
