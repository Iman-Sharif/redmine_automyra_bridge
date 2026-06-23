# frozen_string_literal: true

module AutomyraBridge
  # FAQ Hub status-change webhook dispatcher.
  #
  # Dispatches FAQ Hub status-change events to Hermes so the `faq-review`
  # skill can re-evaluate standards when an FAQ moves between statuses
  # (e.g. active -> review -> archived).
  #
  # Mirrors AutomyraBridge::FaqHubReviewDispatcher (create/update) but emits
  # `redmica.faq_hub.faq_status_changed` with a compact status payload.
  class FaqHubStatusDispatcher
    STATUS_EVENT_TYPE = 'redmica.faq_hub.faq_status_changed'

    def self.dispatch(faq)
      return unless faq.is_a?(FaqHub::Faq)

      payload = build_payload(faq)
      delivery_id = "faq-review-status-#{faq.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(STATUS_EVENT_TYPE, payload, delivery_id)
      log_dispatch(faq)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::FaqHubStatusDispatcher] status dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(faq)
      project = faq.project
      {
        event_type: STATUS_EVENT_TYPE,
        faq_id: faq.id,
        title: faq.title,
        new_status: faq.status,
        old_status: faq.status_before_last_save,
        audience: faq.audience,
        system: faq.system,
        project_id: project&.id,
        project_identifier: project&.identifier,
        project_name: project&.name,
        author_id: faq.author_id,
        author_login: faq.author&.login,
        url: build_url(faq, project),
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.build_url(faq, project)
      return nil unless faq && project

      "#{Setting.protocol}://#{Setting.host_name}/projects/#{project.identifier}/faq_hub/#{faq.id}"
    end
    private_class_method :build_url

    def self.log_dispatch(faq)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'faq_status_changed_webhook_dispatched',
        source: 'faq_hub_status_hook',
        summary: "FAQ status review webhook dispatched for FAQ ##{faq.id} (#{faq.title})",
        target_type: 'FaqHub::Faq',
        target_id: faq.id,
        project_id: faq.project_id,
        user_id: faq.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
