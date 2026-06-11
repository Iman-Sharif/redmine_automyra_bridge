module AutomyraBridge
  module Tools
    class TaskHubCountMyOpenTasksTool < BaseTool
      include SemanticReadHelpers

      NAME = 'task_hub.count_my_open_tasks'.freeze
      LEGACY_ACTION_TYPE = 'task_hub_count_my_open_tasks'.freeze
      DESCRIPTION = 'Count my visible open Task Hub tasks.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {}, required: [] }.freeze

      def self.execute(user:, args: {}) = new.execute(user: user, args: args)

      def required_permission = :view_task_hub_tasks

      private

      def perform(user, _args)
        { count: open_tasks(user).except(:limit).count }
      end

      def open_tasks(user)
        TaskHub::TaskQuery.new.open_tasks(user)
      end
    end
  end
end
