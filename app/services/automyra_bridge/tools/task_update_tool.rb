module AutomyraBridge
  module Tools
    class TaskUpdateTool < BaseTool
      NAME = 'task.update'.freeze
      LEGACY_ACTION_TYPE = 'update_task'.freeze
      DESCRIPTION = 'Update fields on a visible Task Hub task. Provide task_id when the request names a specific task.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          task_id: { type: 'integer' },
          task: {
            type: 'object',
            properties: {
              title: { type: 'string' }, notes: { type: 'string' }, status: { type: 'string' },
              due_date: { type: 'string' }, assigned_to_id: { type: 'integer' }, priority: { type: 'integer' },
              tags: { type: 'string' }, category_id: { type: 'integer' },
              reminder_at: { type: 'string', description: 'Reminder datetime ISO 8601 (e.g. 2026-06-25T08:00:00Z)' },
              reminded: { type: 'boolean', description: 'Whether the reminder has been sent' }
            }
          }
        }
      }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        defined?(TaskHub::Task) && (source_task(job).present? || job.user.allowed_to?(:manage_task_hub_tasks, job.project))
      end

      def call(job, _user, input)
        task = source_task(job, input)
        raise 'Task is no longer available.' unless task
        raise task.errors.full_messages.join(', ') unless task.update(task_attributes(input))

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
