module AutomyraBridge
  # Auto-close webhook dispatcher.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - auto_close_webhook_dispatched: webhook sent to Hermes for deep review
  #   - auto_close_review_passed: Hermes callback closed the issue
  #   - auto_close_review_failed: Hermes callback moved issue to Feedback
  #
  class AutoCloseDispatcher
    EVENT_TYPE = 'redmica.issue_status_changed'.freeze

    def self.dispatch(journal)
      issue = journal.journalized
      return unless issue.is_a?(Issue)

      old_status_detail = journal.details.detect { |d| d.property == 'attr' && d.prop_key == 'status_id' }
      return unless old_status_detail

      old_status = IssueStatus.find_by(id: old_status_detail.old_value.to_i)
      new_status = IssueStatus.find_by(id: old_status_detail.value.to_i)
      payload = build_payload(journal, issue, old_status, new_status)
      delivery_id = "auto-close-issue-#{issue.id}-journal-#{journal.id}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(EVENT_TYPE, payload, delivery_id)
      log_dispatch(journal, issue)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::AutoCloseDispatcher] dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(journal, issue, old_status, new_status)
      {
        event_type: EVENT_TYPE,
        issue_id: issue.id,
        old_status_id: old_status&.id,
        new_status_id: new_status&.id,
        old_status_name: old_status&.name,
        new_status_name: new_status&.name,
        changed_by: journal.user&.login,
        project_id: issue.project&.identifier,
        project_name: issue.project&.name,
        subject: issue.subject,
        description: issue.description.to_s.truncate(2000),
        tracker_name: issue.tracker&.name,
        url: "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue.id}",
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.log_dispatch(journal, issue)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'auto_close_webhook_dispatched',
        source: 'issue_status_hook',
        summary: "Auto-close webhook dispatched for issue ##{issue.id} (#{issue.subject})",
        target_type: 'Issue',
        target_id: issue.id,
        project_id: issue.project_id,
        user_id: journal.user_id
      )
    end
    private_class_method :log_dispatch
  end
end
