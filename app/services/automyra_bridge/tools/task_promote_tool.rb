module AutomyraBridge
  module Tools
    class TaskPromoteTool < BaseTool
      NAME = 'task.promote_to_issue'.freeze
      LEGACY_ACTION_TYPE = 'promote_task'.freeze
      DESCRIPTION = 'Promote the current Task Hub task to an issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { issue: { type: 'object' } } }.freeze

      def required_permission
        :add_issues
      end

      def available?(job)
        source_task(job).present?
      end

      def call(job, user, input)
        task = source_task(job) || raise('Task is no longer available.')
        issue = TaskHub::TaskPromoter.new.promote!(user, task, (input['issue'] || {}).symbolize_keys)
        { task_id: task.id, issue_id: issue.id, status: task.reload.status }
      end

      def verify!(result, _input)
        task = TaskHub::Task.find_by(id: result[:task_id])
        raise 'Task promotion verification failed.' unless task&.promoted_issue_id.to_i == result[:issue_id].to_i
      end
    end
  end
end
