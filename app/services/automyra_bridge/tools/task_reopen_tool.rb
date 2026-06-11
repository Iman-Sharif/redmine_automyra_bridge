module AutomyraBridge
  module Tools
    class TaskReopenTool < BaseTool
      NAME = 'task.reopen'.freeze
      LEGACY_ACTION_TYPE = 'reopen_task'.freeze
      DESCRIPTION = 'Reopen the current Task Hub task to todo or in_progress.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { status: { type: 'string', enum: %w[todo in_progress] } } }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        source_task(job).present?
      end

      def call(job, _user, input)
        task = source_task(job) || raise('Task is no longer available.')
        target = input['status'].presence || input.dig('task', 'status').presence || 'todo'
        task.reopen!(target)
        { task_id: task.id, status: task.status }
      end

      def verify!(result, input)
        target = input['status'].presence || input.dig('task', 'status').presence || 'todo'
        raise 'Task reopen verification failed.' unless TaskHub::Task.find_by(id: result[:task_id])&.status == target
      end
    end
  end
end
