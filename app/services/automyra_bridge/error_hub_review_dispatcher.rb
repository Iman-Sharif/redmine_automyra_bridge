# frozen_string_literal: true

module AutomyraBridge
  # Error Hub review webhook dispatcher.
  #
  # Dispatches Error Hub create/update events to Hermes so the `error-review`
  # skill can run standards checks, auto-fix high-confidence issues, and
  # create linked advisory issues for low-confidence findings.
  #
  # Mirrors AutomyraBridge::WikiReviewDispatcher (bound to WikiContent) and
  # AutomyraBridge::FaqHubReviewDispatcher (bound to FaqHub::Faq). The
  # Automyra-author loop guard and env flag gate are implemented in
  # ErrorHubCreationHook, not duplicated here.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - error_created_webhook_dispatched: webhook sent to Hermes for create
  #   - error_updated_webhook_dispatched: webhook sent to Hermes for update
  #
  class ErrorHubReviewDispatcher
    CREATE_EVENT_TYPE = 'redmica.error_hub.error_created'
    UPDATE_EVENT_TYPE = 'redmica.error_hub.error_updated'
    TEXT_PREVIEW_LIMIT = 2_000

    def self.dispatch_create(error)
      return unless error.is_a?(ErrorHub::Error)

      payload = build_payload(error, CREATE_EVENT_TYPE)
      delivery_id = "error-review-#{error.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(CREATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(error, 'error_created')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::ErrorHubReviewDispatcher] create dispatch failed: #{e.class}: #{e.message}")
    end

    def self.dispatch_update(error)
      return unless error.is_a?(ErrorHub::Error)

      payload = build_payload(error, UPDATE_EVENT_TYPE)
      delivery_id = "error-review-update-#{error.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(UPDATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(error, 'error_updated')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::ErrorHubReviewDispatcher] update dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(error, event_type)
      project = error.project
      {
        event_type: event_type,
        error_id: error.id,
        title: error.title,
        description: error.description.to_s.truncate(TEXT_PREVIEW_LIMIT),
        error_code: error.error_code,
        severity: error.severity,
        status: error.status,
        root_cause: error.root_cause.to_s.truncate(TEXT_PREVIEW_LIMIT),
        solution: error.solution.to_s.truncate(TEXT_PREVIEW_LIMIT),
        prevention: error.prevention.to_s.truncate(TEXT_PREVIEW_LIMIT),
        category: error.attributes['category'],
        tags: error.tags,
        project_id: project&.identifier,
        project_identifier: project&.identifier,
        project_name: project&.name,
        author_id: error.author_id,
        author_login: error.author&.login,
        url: build_url(error, project),
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.build_url(error, project)
      return nil unless error && project

      path = Rails.application.routes.url_helpers.error_hub_path(error)
      "#{Setting.protocol}://#{Setting.host_name}#{path}"
    rescue StandardError
      # Fallback when routes are not loaded (e.g. in non-Rails contexts).
      "#{Setting.protocol}://#{Setting.host_name}/error_hub/#{error.id}"
    end
    private_class_method :build_url

    def self.log_dispatch(error, action_label)
      AutomyraBridge::ActivityLogger.log!(
        action_type: "#{action_label}_webhook_dispatched",
        source: 'error_hub_creation_hook',
        summary: "Error Hub review webhook dispatched for error ##{error.id} (#{error.title})",
        target_type: 'ErrorHub::Error',
        target_id: error.id,
        project_id: error.project_id,
        user_id: error.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
