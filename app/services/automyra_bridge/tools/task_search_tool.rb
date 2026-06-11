module AutomyraBridge
  module Tools
    class TaskSearchTool < BaseTool
      NAME = 'task.search'.freeze
      LEGACY_ACTION_TYPE = 'search_tasks'.freeze
      DESCRIPTION = 'Search visible Task Hub tasks in the current project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } } }.freeze

      def required_permission = :view_task_hub_tasks

      def call(job, user, input)
        query = input['query'].to_s.strip
        limit = [[input['limit'].to_i, 1].max, 10].min
        tasks = TaskHub::Task.visible_to(user).where(project_id: job.project_id).order(updated_at: :desc)
        tasks = tasks.where('LOWER(title) LIKE :q OR LOWER(notes) LIKE :q', q: "%#{query.downcase}%") if query.present?
        { tasks: tasks.limit(limit).map { |task| { id: task.id, title: task.title, status: task.status } } }
      end
    end
  end
end
