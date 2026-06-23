# frozen_string_literal: true

module AutomyraBridge
  # Contacts Hub status-change webhook dispatcher.
  #
  # Dispatches Contacts Hub status-change events to Hermes so the
  # `contacts-review` skill can re-evaluate standards when a contact moves
  # between statuses (e.g. active -> inactive).
  #
  # Mirrors AutomyraBridge::ContactsHubReviewDispatcher (create/update) but
  # emits `redmica.contacts_hub.contact_status_changed` with a PII-redacted
  # status payload.
  class ContactsHubStatusDispatcher
    STATUS_EVENT_TYPE = 'redmica.contacts_hub.contact_status_changed'
    REDACTED_FIELDS = %i[
      name first_name last_name email secondary_email phone mobile
      address_line1 address_line2 city region postal_code country
      birthday description
    ].freeze

    def self.dispatch(contact)
      return unless contact.is_a?(ContactsHub::Contact)

      payload = build_payload(contact)
      delivery_id = "contacts-review-status-#{contact.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(STATUS_EVENT_TYPE, payload, delivery_id)
      log_dispatch(contact)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::ContactsHubStatusDispatcher] status dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(contact)
      project = contact.project
      base = {
        event_type: STATUS_EVENT_TYPE,
        contact_id: contact.id,
        job_title: contact.job_title,
        organization_id: contact.organization_id,
        organization_name: contact.organization&.name,
        new_status: contact.status,
        old_status: contact.status_before_last_save,
        visibility: contact.visibility,
        project_id: project&.id,
        project_identifier: project&.identifier,
        project_name: project&.name,
        author_id: contact.author_id,
        author_login: contact.author&.login,
        assigned_to_id: contact.assigned_to_id,
        tags: extract_tag_names(contact),
        source: contact.source,
        custom_field_names: extract_custom_field_names(contact),
        url: build_url(contact),
        timestamp: Time.current.iso8601
      }

      REDACTED_FIELDS.each do |field|
        base[field] = '[REDACTED]' if contact.respond_to?(field)
      end

      base
    end
    private_class_method :build_payload

    def self.build_url(contact)
      return nil unless contact

      path = Rails.application.routes.url_helpers.contacts_hub_contact_path(contact)
      "#{Setting.protocol}://#{Setting.host_name}#{path}"
    rescue StandardError
      "#{Setting.protocol}://#{Setting.host_name}/contacts_hub/#{contact.id}"
    end
    private_class_method :build_url

    def self.extract_tag_names(contact)
      return [] unless contact.respond_to?(:tags) && contact.tags

      contact.tags.map { |tag| tag&.name }.compact
    rescue StandardError
      []
    end
    private_class_method :extract_tag_names

    def self.extract_custom_field_names(contact)
      return [] unless contact.respond_to?(:custom_field_values)
      return [] unless contact.custom_field_values

      contact.custom_field_values
             .map { |cv| cv.custom_field&.name }
             .compact
             .uniq
    rescue StandardError
      []
    end
    private_class_method :extract_custom_field_names

    def self.log_dispatch(contact)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'contact_status_changed_webhook_dispatched',
        source: 'contacts_hub_status_hook',
        summary: "Contacts status review webhook dispatched for contact ##{contact.id}",
        target_type: 'ContactsHub::Contact',
        target_id: contact.id,
        project_id: contact.project_id,
        user_id: contact.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
