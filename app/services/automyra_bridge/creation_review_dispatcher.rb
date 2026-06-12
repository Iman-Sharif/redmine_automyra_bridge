# frozen_string_literal: true

module AutomyraBridge
  # Creation review webhook dispatcher.
  #
  # Dispatches issue creation events to Hermes for deep review.
  # Event types logged to AutomyraBridgeActivityLog:
  #   - issue_creation_review_webhook_dispatched: webhook sent to Hermes
  #
  class CreationReviewDispatcher
    EVENT_TYPE = 'redmica.issue_created'

    def self.dispatch(issue)
      return unless issue.is_a?(Issue)

      payload = build_payload(issue)
      delivery_id = "issue-creation-#{issue.id}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(EVENT_TYPE, payload, delivery_id)
      log_dispatch(issue)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::CreationReviewDispatcher] dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(issue)
      {
        event_type: EVENT_TYPE,
        issue_id: issue.id,
        subject: issue.subject,
        description: issue.description.to_s.truncate(2000),
        project_id: issue.project&.identifier,
        project_name: issue.project&.name,
        tracker_id: issue.tracker_id,
        tracker_name: issue.tracker&.name,
        author_id: issue.author_id,
        author_name: issue.author&.login,
        created_at: issue.created_on&.iso8601,
        url: "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue.id}",
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.log_dispatch(issue)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'issue_creation_review_webhook_dispatched',
        source: 'issue_creation_hook',
        summary: "Creation review webhook dispatched for issue ##{issue.id} (#{issue.subject})",
        target_type: 'Issue',
        target_id: issue.id,
        project_id: issue.project_id,
        user_id: issue.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
