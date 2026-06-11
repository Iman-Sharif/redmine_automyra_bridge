module AutomyraBridge
  module Tools
    class TaskHubSearchMyTasksTool < BaseTool
      include SemanticReadHelpers

      NAME = 'task_hub.search_my_tasks'.freeze
      LEGACY_ACTION_TYPE = 'task_hub_search_my_tasks'.freeze
      DESCRIPTION = 'Search my visible Task Hub tasks by title or tags.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } }, required: ['query'] }.freeze

      def self.execute(user:, args: {}) = new.execute(user: user, args: args)

      def required_permission = :view_task_hub_tasks

      private

      def perform(user, args)
        query = args['query'].to_s.strip
        tasks = TaskHub::TaskQuery.new.visible_to(user).order(updated_at: :desc)
        if query.present?
          like = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
          tasks = tasks.where('LOWER(task_hub_tasks.title) LIKE :q OR LOWER(task_hub_tasks.tags) LIKE :q', q: like)
        end
        total = tasks.except(:limit).count
        tasks = tasks.limit(compact_limit(args))
        { count: total, tasks: tasks.map { |task| compact_task(task) } }
      end
    end
  end
end
