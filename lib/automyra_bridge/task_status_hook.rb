module AutomyraBridge
  # Task Hub status-change webhook hook.
  #
  # Wires an after_commit callback on TaskHub::Task that fires specifically
  # when the `status` attribute changes. It emits
  # `redmica.task_hub.task_status_changed` so the `task-review` skill can
  # re-evaluate the task for its new status.
  #
  # Mirrors AutomyraBridge::TaskHubCreationHook (create/update) but is
  # intentionally separate so status transitions can be gated independently.
  module TaskStatusHook
    SKIP_KEY = :automyra_bridge_skip_task_hub_review

    def self.install!
      return unless defined?(::TaskHub::Task)
      return if ::TaskHub::Task.included_modules.include?(InstanceMethods)

      ::TaskHub::Task.include InstanceMethods
      ::TaskHub::Task.send(:public, :automyra_bridge_task_hub_review_authored_by_automyra?)
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_task_hub_status_review, on: :update
      end

      def automyra_bridge_task_hub_status_review
        return unless ENV['AUTOMYRA_BRIDGE_TASK_STATUS'].to_s == '1'
        return if Thread.current[SKIP_KEY]
        return unless project
        return if automyra_bridge_task_hub_review_authored_by_automyra?
        return unless saved_change_to_status?

        AutomyraBridge::TaskHubStatusDispatcher.dispatch(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::TaskStatusHook] status dispatch failed: #{e.class}: #{e.message}")
      end

      def automyra_bridge_task_hub_review_authored_by_automyra?
        login = Setting.plugin_redmine_automyra_bridge['webhook_user_login'].to_s.presence
        return false if login.nil?

        bot = User.find_by(login: login)
        return false if bot.nil?

        [author_id, user_id].compact.include?(bot.id)
      end
    end
  end
end
