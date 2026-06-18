# frozen_string_literal: true

module AutomyraBridge
  # FAQ Hub review webhook dispatcher.
  #
  # Dispatches FAQ Hub create/update events to Hermes so the `faq-review`
  # skill can run standards checks, auto-fix high-confidence issues, and
  # create linked advisory issues for low-confidence findings.
  #
  # Mirrors AutomyraBridge::WikiReviewDispatcher (which is bound to
  # WikiContent) but operates on FaqHub::Faq. The Automyra-author loop
  # guard is implemented in FaqHubCreationHook, not duplicated here.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - faq_created_webhook_dispatched: webhook sent to Hermes for create
  #   - faq_updated_webhook_dispatched: webhook sent to Hermes for update
  #
  class FaqHubReviewDispatcher
    CREATE_EVENT_TYPE = 'redmica.faq_hub.faq_created'
    UPDATE_EVENT_TYPE = 'redmica.faq_hub.faq_updated'
    ANSWER_PREVIEW_LIMIT = 2_000

    def self.dispatch_create(faq)
      return unless faq.is_a?(FaqHub::Faq)

      payload = build_payload(faq, CREATE_EVENT_TYPE)
      delivery_id = "faq-review-#{faq.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(CREATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(faq, 'faq_created')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::FaqHubReviewDispatcher] create dispatch failed: #{e.class}: #{e.message}")
    end

    def self.dispatch_update(faq)
      return unless faq.is_a?(FaqHub::Faq)

      payload = build_payload(faq, UPDATE_EVENT_TYPE)
      delivery_id = "faq-review-update-#{faq.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(UPDATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(faq, 'faq_updated')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::FaqHubReviewDispatcher] update dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(faq, event_type)
      project = faq.project
      {
        event_type: event_type,
        faq_id: faq.id,
        title: faq.title,
        short_answer: faq.short_answer,
        answer_preview: faq.answer.to_s.truncate(ANSWER_PREVIEW_LIMIT),
        audience: faq.audience,
        status: faq.status,
        system: faq.system,
        tags: faq.tags,
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

    def self.log_dispatch(faq, action_label)
      AutomyraBridge::ActivityLogger.log!(
        action_type: "#{action_label}_webhook_dispatched",
        source: 'faq_hub_creation_hook',
        summary: "FAQ review webhook dispatched for FAQ ##{faq.id} (#{faq.title})",
        target_type: 'FaqHub::Faq',
        target_id: faq.id,
        project_id: faq.project_id,
        user_id: faq.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
