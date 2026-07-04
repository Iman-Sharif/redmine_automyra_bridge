module AutomyraBridge
  module Tools
    class TaskCreateTool < BaseTool
      NAME = 'task.create'.freeze
      LEGACY_ACTION_TYPE = 'create_task'.freeze
      DESCRIPTION = 'Create a Task Hub task in the current project.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = {
        type: 'object',
        required: ['task'],
        properties: {
          task: {
            type: 'object',
            required: ['title'],
            properties: {
              title: { type: 'string' }, notes: { type: 'string' }, status: { type: 'string' },
              due_date: { type: 'string' }, assigned_to_id: { type: 'integer' }, priority: { type: 'integer' },
              tags: { type: 'string' }, category_id: { type: 'integer' },
              reminder_at: { type: 'string', description: 'Reminder datetime ISO 8601 (e.g. 2026-06-25T08:00:00Z)' },
              reminded: { type: 'boolean', description: 'Whether the reminder has been sent' },
              waiting_for_contact_id: { type: 'integer', description: 'Contact ID the task is waiting on (required when status is waiting)' }
            }
          }
        }
      }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def call(job, user, input)
        attrs = task_attributes(input).merge('project_id' => job.project_id)
        task = TaskHub::TaskCreator.new.create_standalone(user, attrs.symbolize_keys)
        raise task.errors.full_messages.join(', ') unless task.persisted?

        { task_id: task.id }
      end

      def verify!(result, input)
        task = TaskHub::Task.find_by(id: result[:task_id])
        raise 'Task write verification failed.' unless task

        task_attributes(input).each do |key, value|
          next if value.blank? || !task.respond_to?(key)
          raise "Task write verification failed for #{key}." unless task.public_send(key).to_s == value.to_s
        end
      end
    end
  end
end
