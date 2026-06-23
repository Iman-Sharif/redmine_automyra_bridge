module AutomyraBridge
  # Contacts Hub status-change webhook hook.
  #
  # Wires an after_commit callback on ContactsHub::Contact that fires
  # specifically when the `status` attribute changes. It emits
  # `redmica.contacts_hub.contact_status_changed` so the `contacts-review`
  # skill can re-evaluate the contact for its new status.
  #
  # Mirrors AutomyraBridge::ContactsHubCreationHook (create/update) but is
  # intentionally separate so status transitions can be gated independently.
  # PII redaction is handled by ContactsHubStatusDispatcher.
  module ContactsStatusHook
    def self.install!
      return unless defined?(ContactsHub::Contact)
      return if ContactsHub::Contact.included_modules.include?(InstanceMethods)

      ContactsHub::Contact.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_contacts_hub_status_review, on: :update
      end

      private

      def automyra_bridge_contacts_hub_status_review
        return unless ENV['AUTOMYRA_BRIDGE_CONTACTS_STATUS'].to_s == '1'
        return if Thread.current[:automyra_bridge_skip_webhook]
        return unless project
        return if automyra_bridge_authored_by_automyra?
        return unless saved_change_to_status? || saved_change_to_visibility?

        AutomyraBridge::ContactsHubStatusDispatcher.dispatch(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::ContactsStatusHook] status dispatch failed: #{e.message}")
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
