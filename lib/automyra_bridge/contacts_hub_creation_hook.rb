module AutomyraBridge
  # Contacts Hub review webhook hook.
  #
  # Installs after_commit callbacks on ContactsHub::Contact to dispatch a
  # webhook to Hermes so the `contact-review` skill can run standards checks,
  # auto-fix high-confidence issues, and create linked advisory issues for
  # low-confidence findings.
  #
  # Mirrors AutomyraBridge::FaqHubCreationHook (bound to FaqHub::Faq) and
  # AutomyraBridge::ErrorHubCreationHook (bound to ErrorHub::Error). The
  # create callback always fires on commit; the update callback fires only
  # when a review-relevant attribute changes (name / job_title / status /
  # visibility / organization_id) so metadata-only edits (e.g. touched
  # timestamps, follow-up dates) do not flood the review queue.
  #
  # The Automyra-author loop guard is applied only to the update callback;
  # create events (including bot-authored records from MCP tools) always
  # dispatch so the bot can review records it creates. Global contacts
  # (project_id = nil) are dispatched without a project guard.
  #
  # Payload redaction is implemented in ContactsHubReviewDispatcher — PII
  # fields (email, secondary_email, phone, mobile, address_*, birthday,
  # description, notes) are intentionally omitted from the webhook body.
  module ContactsHubCreationHook
    def self.install!
      return unless defined?(ContactsHub::Contact)
      return if ContactsHub::Contact.included_modules.include?(InstanceMethods)

      ContactsHub::Contact.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_contacts_hub_review, on: :create
        after_commit :automyra_bridge_contacts_hub_update_review, on: :update
      end

      private

      def automyra_bridge_contacts_hub_review
        return unless ENV['AUTOMYRA_BRIDGE_CONTACTS_REVIEW'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]

        AutomyraBridge::ContactsHubReviewDispatcher.dispatch_create(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::ContactsHubCreationHook] create dispatch failed: #{e.message}")
      end

      def automyra_bridge_contacts_hub_update_review
        return unless ENV['AUTOMYRA_BRIDGE_CONTACTS_REVIEW'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return if automyra_bridge_authored_by_automyra?
        return unless contacts_hub_review_relevant_change?

        AutomyraBridge::ContactsHubReviewDispatcher.dispatch_update(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::ContactsHubCreationHook] update dispatch failed: #{e.message}")
      end

      # Returns true if any review-relevant attribute changed.
      # All listed columns exist on `contacts_hub_contacts`, so the
      # `saved_change_to_<attr>?` predicates are safe here. The same pattern
      # is used by the wiki / FAQ / Error Hub hooks.
      def contacts_hub_review_relevant_change?
        saved_change_to_name? ||
          saved_change_to_job_title? ||
          saved_change_to_status? ||
          saved_change_to_visibility? ||
          saved_change_to_organization_id?
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
