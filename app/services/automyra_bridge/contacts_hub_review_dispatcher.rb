# frozen_string_literal: true

module AutomyraBridge
  # Contacts Hub review webhook dispatcher.
  #
  # Dispatches Contacts Hub create/update events to Hermes so the
  # `contact-review` skill can run standards checks, auto-fix high-confidence
  # issues, and create linked advisory issues for low-confidence findings.
  #
  # Mirrors AutomyraBridge::FaqHubReviewDispatcher (bound to FaqHub::Faq) and
  # AutomyraBridge::ErrorHubReviewDispatcher (bound to ErrorHub::Error). The
  # Automyra-author loop guard and env flag gate are implemented in
  # ContactsHubCreationHook, not duplicated here.
  #
  # PAYLOAD REDACTION: The webhook payload is intentionally PII-redacted.
  # The following sensitive fields are NEVER included in the payload, even
  # though they exist on the model:
  #
  #   - email, secondary_email, phone, mobile
  #   - address_line1, address_line2, city, region, postal_code, country
  #   - birthday
  #   - description (free-text notes on the contact)
  #   - note bodies (ContactsHub::Note has_many association)
  #
  # Only metadata, identifiers, and the configured tag / custom-field NAMES
  # (never values) are sent.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - contact_created_webhook_dispatched: webhook sent to Hermes for create
  #   - contact_updated_webhook_dispatched: webhook sent to Hermes for update
  #
  class ContactsHubReviewDispatcher
    CREATE_EVENT_TYPE = 'redmica.contacts_hub.contact_created'
    UPDATE_EVENT_TYPE = 'redmica.contacts_hub.contact_updated'
    TEXT_PREVIEW_LIMIT = 2_000

    def self.dispatch_create(contact)
      return unless contact.is_a?(ContactsHub::Contact)

      payload = build_payload(contact, CREATE_EVENT_TYPE)
      delivery_id = "contacts-review-#{contact.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(CREATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(contact, 'contact_created')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::ContactsHubReviewDispatcher] create dispatch failed: #{e.class}: #{e.message}")
    end

    def self.dispatch_update(contact)
      return unless contact.is_a?(ContactsHub::Contact)

      payload = build_payload(contact, UPDATE_EVENT_TYPE)
      delivery_id = "contacts-review-update-#{contact.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(UPDATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(contact, 'contact_updated')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::ContactsHubReviewDispatcher] update dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(contact, event_type)
      project = contact.project
      {
        event_type: event_type,
        contact_id: contact.id,
        name: contact.name,
        job_title: contact.job_title,
        organization_id: contact.organization_id,
        organization_name: contact.organization&.name,
        status: contact.status,
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
    end
    private_class_method :build_payload

    def self.build_url(contact)
      return nil unless contact

      path = Rails.application.routes.url_helpers.contacts_hub_contact_path(contact)
      "#{Setting.protocol}://#{Setting.host_name}#{path}"
    rescue StandardError
      # Fallback when routes are not loaded (e.g. in non-Rails contexts).
      "#{Setting.protocol}://#{Setting.host_name}/contacts_hub/#{contact.id}"
    end
    private_class_method :build_url

    # Tag names only — never tag metadata. Returns an empty array when the
    # association is absent, nil, or raises.
    def self.extract_tag_names(contact)
      return [] unless contact.respond_to?(:tags) && contact.tags

      contact.tags.map { |tag| tag&.name }.compact
    rescue StandardError
      []
    end
    private_class_method :extract_tag_names

    # Custom field NAMES only — never values. The Contact model does not
    # currently `acts_as_customizable`, so this method is defensive: it
    # returns an empty array if the model does not respond to
    # `custom_field_values`, and rescues any unexpected errors from the
    # association lookup. The key is always present in the payload.
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

    def self.log_dispatch(contact, action_label)
      AutomyraBridge::ActivityLogger.log!(
        action_type: "#{action_label}_webhook_dispatched",
        source: 'contacts_hub_creation_hook',
        summary: "Contacts review webhook dispatched for contact ##{contact.id} (#{contact.name})",
        target_type: 'ContactsHub::Contact',
        target_id: contact.id,
        project_id: contact.project_id,
        user_id: contact.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
