module AutomyraBridge
  module Tools
    class TaskHubGetMyOpenTasksTool < BaseTool
      include SemanticReadHelpers

      NAME = 'task_hub.get_my_open_tasks'.freeze
      LEGACY_ACTION_TYPE = 'task_hub_get_my_open_tasks'.freeze
      DESCRIPTION = 'List my visible open Task Hub tasks.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { limit: { type: 'integer' } }, required: [] }.freeze

      def self.execute(user:, args: {}) = new.execute(user: user, args: args)

      def required_permission = :view_task_hub_tasks

      private

      def perform(user, args)
        tasks = TaskHub::TaskQuery.new.open_tasks(user).order(due_date: :asc, updated_at: :desc)
        total = tasks.except(:limit).count
        tasks = tasks.limit(compact_limit(args))
        { count: total, tasks: tasks.map { |task| compact_task(task) } }
      end
    end
  end
end
