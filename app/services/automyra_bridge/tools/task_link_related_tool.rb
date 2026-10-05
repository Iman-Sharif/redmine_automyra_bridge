module AutomyraBridge
  module Tools
    class TaskLinkRelatedTool < BaseTool
      NAME = 'task.link_related'.freeze
      LEGACY_ACTION_TYPE = 'task_link_related'.freeze
      DESCRIPTION = 'Create an explicit related_to dependency between two Task Hub tasks.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          task_id: { type: 'integer', description: 'Source task ID' },
          related_task_id: { type: 'integer', description: 'Target related task ID' }
        },
        required: %w[task_id related_task_id]
      }.freeze

      def required_permission = :manage_task_hub_tasks

      def call(_job, user, input)
        task_id = input['task_id'] || input[:task_id]
        related_task_id = input['related_task_id'] || input[:related_task_id]

        source = TaskHub::Task.visible_to(user).find_by(id: task_id)
        return { error: 'Source task not found or not visible' } unless source

        target = TaskHub::Task.visible_to(user).find_by(id: related_task_id)
        return { error: 'Related task not found or not visible' } unless target

        return { error: 'Cannot link task to itself' } if source.id == target.id

        dependency = TaskHub::TaskDependency.find_or_create_by!(
          predecessor_id: source.id,
          successor_id: target.id
        ) do |dep|
          dep.dependency_type = 'related_to'
        end

        {
          dependency_id: dependency.id,
          source_task_id: source.id,
          related_task_id: target.id
        }
      end

      def verify!(result, input)
        return true if result[:error].present?

        TaskHub::TaskDependency.exists?(
          predecessor_id: input['task_id'] || input[:task_id],
          successor_id: input['related_task_id'] || input[:related_task_id]
        )
      end
    end
  end
end
