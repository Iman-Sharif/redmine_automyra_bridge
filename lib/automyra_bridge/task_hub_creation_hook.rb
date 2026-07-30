module AutomyraBridge
  # Wires the Task Hub review webhook hook onto `TaskHub::Task`.
  #
  # Mirrors the wiki / FAQ / Error Hub hook conventions:
  #   - feature-flagged via `ENV['AUTOMYRA_BRIDGE_TASK_REVIEW']`
  #   - thread-local `:automyra_bridge_skip_task_hub_review` opt-out
  #   - skips records authored by the configured bot user
  #
  # On `:create` commit -> `redmica.task_hub.task_created`.
  # On `:update` commit, only when at least one of the watched attributes
  # actually changed -> `redmica.task_hub.task_updated`. This avoids firing on
  # metadata-only writes (touch, position counters, cached columns).
  #
  # Both events route through `TaskHubReviewDispatcher` and land on
  # `hermes_webhook_url_task_review`.
  module TaskHubCreationHook
    SKIP_KEY = :automyra_bridge_skip_task_hub_review

    # Column names on `task_hub_tasks`. The payload exposes these under
    # friendly names (`subject` for `title`, `parent_id` for
    # `parent_task_id`); the change-detection guard here uses the real column
    # names because that is what `saved_changes` is keyed by.
    WATCHED_UPDATE_ATTRIBUTES = %w[
      title
      notes
      due_date
      priority
      status
      assigned_to_id
      parent_task_id
    ].freeze

    def self.install!
      return unless defined?(::TaskHub::Task)

      unless ::TaskHub::Task.included_modules.include?(InstanceMethods)
        ::TaskHub::Task.include InstanceMethods
        ::TaskHub::Task.after_commit :automyra_bridge_dispatch_task_hub_review_create, on: :create
        ::TaskHub::Task.after_commit :automyra_bridge_dispatch_task_hub_review_update, on: :update
      end

      # TaskHub::Task ends with a `private` modifier, so any module included
      # into it after class load inherits that visibility. Re-declare the bot
      # check as public so `self.dispatch` (a class method) can call it on a
      # task instance without raising NoMethodError: private method.
      ::TaskHub::Task.send(:public, :automyra_bridge_task_hub_review_authored_by_automyra?)
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      # Returns true when at least one review-relevant attribute changed.
      # Uses `saved_changes.key?` rather than `saved_change_to_<attr>?` so the
      # hook stays safe even if the underlying schema does not yet include
      # every documented column (matches the Error Hub hook pattern).
      def automyra_bridge_task_hub_review_relevant_change?
        changed = saved_changes
        AutomyraBridge::TaskHubCreationHook::WATCHED_UPDATE_ATTRIBUTES.any? do |attr|
          changed.key?(attr)
        end
      end

      def automyra_bridge_dispatch_task_hub_review_create
        AutomyraBridge::TaskHubCreationHook.dispatch(self, :create)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::TaskHubCreationHook] create dispatch failed: #{e.class}: #{e.message}")
      end

      def automyra_bridge_dispatch_task_hub_review_update
        return unless automyra_bridge_task_hub_review_relevant_change?
        return if automyra_bridge_task_hub_review_authored_by_automyra?

        AutomyraBridge::TaskHubCreationHook.dispatch(self, :update)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::TaskHubCreationHook] update dispatch failed: #{e.class}: #{e.message}")
      end

      def automyra_bridge_task_hub_review_authored_by_automyra?
        login = Setting.plugin_redmine_automyra_bridge['webhook_user_login'].to_s.presence
        return false if login.nil?

        bot = User.find_by(login: login)
        return false if bot.nil?

        [author_id, user_id].compact.include?(bot.id)
      end
    end

    def self.dispatch(task, action)
      return unless ENV['AUTOMYRA_BRIDGE_TASK_REVIEW'].to_s == '1'
      return unless task.is_a?(::TaskHub::Task)
      return if Thread.current[SKIP_KEY]

      if action == :create
        AutomyraBridge::TaskHubReviewDispatcher.dispatch_created(task)
      else
        AutomyraBridge::TaskHubReviewDispatcher.dispatch_updated(task)
      end
    end
  end
end
