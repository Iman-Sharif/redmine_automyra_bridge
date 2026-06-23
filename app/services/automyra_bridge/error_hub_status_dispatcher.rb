# frozen_string_literal: true

module AutomyraBridge
  # Error Hub status-change webhook dispatcher.
  #
  # Dispatches Error Hub status-change events to Hermes so the `error-review`
  # skill can re-evaluate standards when an error moves between statuses
  # (e.g. open -> resolved -> closed).
  #
  # Mirrors AutomyraBridge::ErrorHubReviewDispatcher (create/update) but emits
  # `redmica.error_hub.error_status_changed` with a compact status payload.
  class ErrorHubStatusDispatcher
    STATUS_EVENT_TYPE = 'redmica.error_hub.error_status_changed'

    def self.dispatch(error)
      return unless error.is_a?(ErrorHub::Error)

      payload = build_payload(error)
      delivery_id = "error-review-status-#{error.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(STATUS_EVENT_TYPE, payload, delivery_id)
      log_dispatch(error)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::ErrorHubStatusDispatcher] status dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(error)
      project = error.project
      {
        event_type: STATUS_EVENT_TYPE,
        error_id: error.id,
        title: error.title,
        new_status: error.status,
        old_status: error.status_before_last_save,
        severity: error.severity,
        error_code: error.error_code,
        project_id: project&.id,
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
      "#{Setting.protocol}://#{Setting.host_name}/error_hub/#{error.id}"
    end
    private_class_method :build_url

    def self.log_dispatch(error)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'error_status_changed_webhook_dispatched',
        source: 'error_hub_status_hook',
        summary: "Error status review webhook dispatched for error ##{error.id} (#{error.title})",
        target_type: 'ErrorHub::Error',
        target_id: error.id,
        project_id: error.project_id,
        user_id: error.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
