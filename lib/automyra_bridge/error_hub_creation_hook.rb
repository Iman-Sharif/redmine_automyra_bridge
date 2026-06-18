module AutomyraBridge
  # Error Hub review webhook hook.
  #
  # Installs after_commit callbacks on ErrorHub::Error to dispatch a webhook
  # to Hermes so the `error-review` skill can run standards checks, auto-fix
  # high-confidence issues, and create linked advisory issues for
  # low-confidence findings.
  #
  # Mirrors AutomyraBridge::WikiCreationHook (bound to WikiContent) and
  # AutomyraBridge::FaqHubCreationHook (bound to FaqHub::Faq). The create
  # callback always fires on commit; the update callback fires only when a
  # review-relevant attribute changes (title / description / error_code /
  # severity / root_cause / solution / prevention / category / status) so
  # metadata-only edits do not flood the review queue.
  #
  # The Automyra-author loop guard prevents webhooks from re-firing on edits
  # made by the configured bot user.
  module ErrorHubCreationHook
    def self.install!
      return unless defined?(ErrorHub::Error)
      return if ErrorHub::Error.included_modules.include?(InstanceMethods)

      ErrorHub::Error.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_error_hub_review, on: :create
        after_commit :automyra_bridge_error_hub_update_review, on: :update
      end

      private

      def automyra_bridge_error_hub_review
        return unless ENV['AUTOMYRA_BRIDGE_ERROR_REVIEW'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project
        return if automyra_bridge_authored_by_automyra?

        AutomyraBridge::ErrorHubReviewDispatcher.dispatch_create(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::ErrorHubCreationHook] create dispatch failed: #{e.message}")
      end

      def automyra_bridge_error_hub_update_review
        return unless ENV['AUTOMYRA_BRIDGE_ERROR_REVIEW'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project
        return if automyra_bridge_authored_by_automyra?
        return unless error_hub_review_relevant_change?

        AutomyraBridge::ErrorHubReviewDispatcher.dispatch_update(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::ErrorHubCreationHook] update dispatch failed: #{e.message}")
      end

      # Returns true if any review-relevant attribute changed. Uses
      # `saved_changes.key?` rather than `saved_change_to_<attr>?` so the
      # hook stays safe even if the underlying schema does not yet include
      # every documented column (e.g. `category` is in the spec but is not
      # currently a column on error_hub_errors).
      def error_hub_review_relevant_change?
        changed = saved_changes
        changed.key?('title') ||
          changed.key?('description') ||
          changed.key?('error_code') ||
          changed.key?('severity') ||
          changed.key?('root_cause') ||
          changed.key?('solution') ||
          changed.key?('prevention') ||
          changed.key?('category') ||
          changed.key?('status')
      end

      def automyra_bridge_authored_by_automyra?
        login = Setting.plugin_redmine_automyra_bridge['webhook_user_login'].to_s.presence
        return false if login.nil?

        bot = User.find_by(login: login)
        return false if bot.nil?

        author_id == bot.id
      end
    end
  end
end
