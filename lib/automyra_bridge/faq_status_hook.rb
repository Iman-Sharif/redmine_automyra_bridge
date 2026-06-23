module AutomyraBridge
  # FAQ Hub status-change webhook hook.
  #
  # Wires an after_commit callback on FaqHub::Faq that fires specifically
  # when the `status` attribute changes. It emits
  # `redmica.faq_hub.faq_status_changed` so the `faq-review` skill can
  # re-evaluate the FAQ for its new status.
  #
  # Mirrors AutomyraBridge::FaqHubCreationHook (create/update) but is
  # intentionally separate so status transitions can be gated independently.
  module FaqStatusHook
    def self.install!
      return unless defined?(FaqHub::Faq)
      return if FaqHub::Faq.included_modules.include?(InstanceMethods)

      FaqHub::Faq.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_faq_hub_status_review, on: :update
      end

      private

      def automyra_bridge_faq_hub_status_review
        return unless ENV['AUTOMYRA_BRIDGE_FAQ_STATUS'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project
        return if automyra_bridge_authored_by_automyra?
        return unless saved_change_to_status? || saved_change_to_audience? || saved_change_to_system?

        AutomyraBridge::FaqHubStatusDispatcher.dispatch(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::FaqStatusHook] status dispatch failed: #{e.message}")
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
