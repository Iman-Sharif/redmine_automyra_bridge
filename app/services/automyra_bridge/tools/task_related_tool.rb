module AutomyraBridge
  module Tools
    class TaskRelatedTool < BaseTool
      NAME = 'task.related'.freeze
      LEGACY_ACTION_TYPE = 'task_related'.freeze
      DESCRIPTION = 'Find related Task Hub tasks using weighted scoring (explicit dependencies, same project, shared tags with IDF discount).'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = {
        type: 'object',
        properties: {
          task_id: { type: 'integer', description: 'Task ID to find related tasks for' }
        },
        required: ['task_id']
      }.freeze

      def required_permission = :view_task_hub_tasks

      def call(job, user, input)
        task_id = input['task_id'] || input[:task_id]
        task = TaskHub::Task.visible_to(user).find_by(id: task_id)
        return { error: 'Task not found or not visible' } unless task

        related = TaskHub::TaskQuery.new.related_to(task)
        {
          related_tasks: related.map { |t| serialize(t, task) }
        }
      end

      private

      def serialize(related_task, source_task)
        {
          id: related_task.id,
          title: related_task.title,
          status: related_task.status,
          project_id: related_task.project_id,
          project_name: related_task.project&.name,
          match_reason: infer_match_reason(related_task, source_task)
        }
      end

      def infer_match_reason(related_task, source_task)
        if TaskHub::TaskDependency.exists?(
          predecessor_id: [source_task.id, related_task.id],
          successor_id: [source_task.id, related_task.id]
        )
          'explicit_dependency'
        elsif related_task.project_id == source_task.project_id
          'same_project'
        else
          'shared_tags'
        end
      end
    end
  end
end