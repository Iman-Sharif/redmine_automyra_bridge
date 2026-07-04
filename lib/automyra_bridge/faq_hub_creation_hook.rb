module AutomyraBridge
  module FaqHubCreationHook
    def self.install!
      return unless defined?(FaqHub::Faq)
      return if FaqHub::Faq.included_modules.include?(InstanceMethods)

      FaqHub::Faq.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_faq_hub_review, on: :create
        after_commit :automyra_bridge_faq_hub_update_review, on: :update
      end

      private

      def automyra_bridge_faq_hub_review
        return unless ENV['AUTOMYRA_BRIDGE_FAQ_REVIEW'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project

        AutomyraBridge::FaqHubReviewDispatcher.dispatch_create(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::FaqHubCreationHook] create dispatch failed: #{e.message}")
      end

      def automyra_bridge_faq_hub_update_review
        return unless ENV['AUTOMYRA_BRIDGE_FAQ_REVIEW'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project
        return if automyra_bridge_authored_by_automyra?
        return unless saved_change_to_title? ||
                      saved_change_to_short_answer? ||
                      saved_change_to_answer? ||
                      saved_change_to_audience? ||
                      saved_change_to_status? ||
                      saved_change_to_system?

        AutomyraBridge::FaqHubReviewDispatcher.dispatch_update(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::FaqHubCreationHook] update dispatch failed: #{e.message}")
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
