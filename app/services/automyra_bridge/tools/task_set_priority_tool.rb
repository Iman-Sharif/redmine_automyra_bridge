module AutomyraBridge
  module Tools
    class TaskSetPriorityTool < BaseTool
      NAME = 'task.set_priority'.freeze
      LEGACY_ACTION_TYPE = 'set_task_priority'.freeze
      DESCRIPTION = 'Set priority on the current Task Hub task.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['task'], properties: { task: { type: 'object', required: ['priority'], properties: { priority: { type: 'integer' } } } } }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        source_task(job).present?
      end

      def call(job, _user, input)
        task = source_task(job) || raise('Task is no longer available.')
        priority = input.dig('task', 'priority') || input['priority']
        task.update!(priority: priority)
        { task_id: task.id, priority: task.priority }
      end

      def verify!(result, input)
        priority = input.dig('task', 'priority') || input['priority']
        raise 'Task priority verification failed.' unless TaskHub::Task.find_by(id: result[:task_id])&.priority.to_i == priority.to_i
      end
    end
  end
end
