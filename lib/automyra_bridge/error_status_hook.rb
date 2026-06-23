module AutomyraBridge
  # Error Hub status-change webhook hook.
  #
  # Wires an after_commit callback on ErrorHub::Error that fires specifically
  # when the `status` attribute changes. It emits
  # `redmica.error_hub.error_status_changed` so the `error-review` skill can
  # re-evaluate the error for its new status.
  #
  # Mirrors AutomyraBridge::FaqStatusHook but targets ErrorHub::Error.
  module ErrorStatusHook
    def self.install!
      return unless defined?(ErrorHub::Error)
      return if ErrorHub::Error.included_modules.include?(InstanceMethods)

      ErrorHub::Error.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_error_hub_status_review, on: :update
      end

      private

      def automyra_bridge_error_hub_status_review
        return unless ENV['AUTOMYRA_BRIDGE_ERROR_STATUS'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project
        return if automyra_bridge_authored_by_automyra?
        return unless saved_change_to_status?

        AutomyraBridge::ErrorHubStatusDispatcher.dispatch(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::ErrorStatusHook] status dispatch failed: #{e.message}")
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
