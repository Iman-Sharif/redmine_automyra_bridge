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

        AutomyraBridge::CreationReviewDispatcher.dispatch(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::IssueCreationHook] Error: #{e.message}")
      end
    end
  end
end
