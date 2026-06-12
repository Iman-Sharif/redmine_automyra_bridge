module AutomyraBridge
  module Tools
    class TaskSetDueDateTool < BaseTool
      include ResolvesTarget

      NAME = 'task.set_due_date'.freeze
      LEGACY_ACTION_TYPE = 'set_task_due_date'.freeze
      DESCRIPTION = 'Set due date on the current Task Hub task.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['task'], properties: { task: { type: 'object', required: ['due_date'], properties: { due_date: { type: 'string' } } } } }.freeze

      self.target_resolver = :source_task
      self.target_name = 'Task'
      self.target_id_key = :task_id

      def required_permission
        :manage_task_hub_tasks
      end

      def call(job, _user, input)
        task = resolve_target!(job)
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
