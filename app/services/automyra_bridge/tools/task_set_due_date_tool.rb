module AutomyraBridge
  module Tools
    class TaskSetDueDateTool < BaseTool
      NAME = 'task.set_due_date'.freeze
      LEGACY_ACTION_TYPE = 'set_task_due_date'.freeze
      DESCRIPTION = 'Set due date on the current Task Hub task.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['task'], properties: { task: { type: 'object', required: ['due_date'], properties: { due_date: { type: 'string' } } } } }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        source_task(job).present?
      end

      def call(job, _user, input)
        task = source_task(job) || raise('Task is no longer available.')
        due_date = input.dig('task', 'due_date') || input['due_date']
        task.update!(due_date: due_date)
        { task_id: task.id, due_date: task.due_date&.to_s }
      end

      def verify!(result, input)
        due_date = input.dig('task', 'due_date') || input['due_date']
        raise 'Task due date verification failed.' unless TaskHub::Task.find_by(id: result[:task_id])&.due_date&.to_s == due_date.to_s
      end
    end
  end
end
