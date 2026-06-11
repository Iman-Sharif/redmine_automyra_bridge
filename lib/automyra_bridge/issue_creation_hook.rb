module AutomyraBridge
  module IssueCreationHook
    def self.install!
      return unless defined?(Issue)
      return if Issue.included_modules.include?(InstanceMethods)

      Issue.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_creation_review, on: :create
      end

      private

      def automyra_bridge_creation_review
        return unless ENV['AUTOMYRA_BRIDGE_CREATION_REVIEW'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project
        return if bot_user?(author_id)

        AutomyraBridge::CreationReviewDispatcher.dispatch(self)
      rescue => e
        Rails.logger.error("[AutomyraBridge::IssueCreationHook] Error: #{e.message}")
      end

      def bot_user?(user_id)
        user = User.find_by(id: user_id)
        return false unless user
        bot_login = Setting.plugin_redmine_automyra_bridge['webhook_user_login'].presence || 'automyra'
        user.login.to_s.downcase == bot_login.to_s.downcase
      end
    end
  end
end