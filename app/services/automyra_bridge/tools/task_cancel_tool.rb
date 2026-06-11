module AutomyraBridge
  module Tools
    class TaskCancelTool < BaseTool
      NAME = 'task.cancel'.freeze
      LEGACY_ACTION_TYPE = 'cancel_task'.freeze
      DESCRIPTION = 'Soft-cancel a visible Task Hub task. Provide task_id when the request names a specific task.'.freeze
      RISK_LEVEL = 'destructive_soft'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { task_id: { type: 'integer' } } }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        defined?(TaskHub::Task) && (source_task(job).present? || job.user.allowed_to?(:manage_task_hub_tasks, job.project))
      end

      def call(job, _user, input)
        task = source_task(job, input)
        raise 'Task is no longer available.' unless task

        task.cancel!
        { task_id: task.id, status: task.status }
      end

      def verify!(result, _input)
        task = TaskHub::Task.find_by(id: result[:task_id])
        raise 'Task cancel verification failed.' unless task&.status == 'cancelled'
      end
    end
  end
end
