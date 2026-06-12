module AutomyraBridge
  module Tools
    class TaskAssignTool < BaseTool
      NAME = 'task.assign'.freeze
      LEGACY_ACTION_TYPE = 'assign_task'.freeze
      DESCRIPTION = 'Assign the current Task Hub task to a user.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['assignment'], properties: { assignment: { type: 'object', required: ['assigned_to_id'], properties: { assigned_to_id: { type: 'integer' } } } } }.freeze

      def required_permission
        :manage_task_hub_tasks
      end

      def available?(job)
        source_task(job).present?
      end

      def call(job, _user, input)
        task = source_task(job) || raise('Task is no longer available.')
        assigned_to_id = input.dig('assignment', 'assigned_to_id') || input['assigned_to_id']
        raise 'Assigned user is not available.' unless User.active.find_by(id: assigned_to_id)

        task.update!(assigned_to_id: assigned_to_id)
        { task_id: task.id, assigned_to_id: task.assigned_to_id }
      end

      def verify!(result, input)
        assigned_to_id = input.dig('assignment', 'assigned_to_id') || input['assigned_to_id']
        raise 'Task assignment verification failed.' unless TaskHub::Task.find_by(id: result[:task_id])&.assigned_to_id.to_i == assigned_to_id.to_i
      end
    end
  end
end
