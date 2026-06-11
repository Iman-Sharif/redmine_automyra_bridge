module AutomyraBridge
  module Tools
    class TaskCompleteTool < BaseTool
      NAME = 'task.complete'.freeze
      LEGACY_ACTION_TYPE = 'complete_task'.freeze
      DESCRIPTION = 'Mark the current Task Hub task done.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { task_id: { type: 'integer' } } }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        source_task(job).present?
      end

      def call(job, _user, _input)
        task = source_task(job) || raise('Task is no longer available.')
        task.complete!
        { task_id: task.id, status: task.status }
      end

      def verify!(result, _input)
        raise 'Task complete verification failed.' unless TaskHub::Task.find_by(id: result[:task_id])&.status == 'done'
      end
    end
  end
end
