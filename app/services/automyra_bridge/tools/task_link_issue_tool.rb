module AutomyraBridge
  module Tools
    class TaskLinkIssueTool < BaseTool
      NAME = 'task.link_issue'.freeze
      LEGACY_ACTION_TYPE = 'link_task_issue'.freeze
      DESCRIPTION = 'Link the current Task Hub task to a visible issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['target'], properties: { target: { type: 'object', required: ['issue_id'], properties: { issue_id: { type: 'integer' } } } } }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        source_task(job).present?
      end

      def call(job, user, input)
        task = source_task(job) || raise('Task is no longer available.')
        issue_id = input.dig('target', 'issue_id') || input['issue_id']
        issue = Issue.visible(user).find_by(id: issue_id)
        raise 'Issue is not visible.' unless issue
        task.update!(issue_id: issue.id, project_id: issue.project_id)
        { task_id: task.id, issue_id: task.issue_id }
      end

      def verify!(result, input)
        issue_id = input.dig('target', 'issue_id') || input['issue_id']
        raise 'Task issue link verification failed.' unless TaskHub::Task.find_by(id: result[:task_id])&.issue_id.to_i == issue_id.to_i
      end
    end
  end
end
