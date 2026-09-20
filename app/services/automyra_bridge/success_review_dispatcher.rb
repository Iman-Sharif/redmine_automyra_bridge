# frozen_string_literal: true

module AutomyraBridge
  # Success review webhook dispatcher for closed issues and done Task Hub tasks.
  #
  # Dispatches `redmica.success_review.issue` and `redmica.success_review.task`
  # events to Hermes so the `success-validation` skill can run the 4-gate
  # procurement benefit validation in isolation — without triggering the full
  # issue-deep-review (which could reopen closed issues) or task-review.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - success_review_issue_dispatched: webhook sent for an issue
  #   - success_review_task_dispatched: webhook sent for a task
  #
  class SuccessReviewDispatcher
    ISSUE_EVENT_TYPE = 'redmica.success_review.issue'
    TASK_EVENT_TYPE = 'redmica.success_review.task'

    def self.dispatch_issue(issue)
      return unless issue.is_a?(::Issue)

      payload = build_issue_payload(issue)
      delivery_id = "success-review-issue-#{issue.id}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(ISSUE_EVENT_TYPE, payload, delivery_id)
      log_dispatch('success_review_issue_dispatched', 'Issue', issue.id, issue.project_id, issue.subject)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::SuccessReviewDispatcher] issue dispatch failed: #{e.class}: #{e.message}")
    end

    def self.dispatch_task(task)
      return unless task.is_a?(::TaskHub::Task)

      payload = build_task_payload(task)
      delivery_id = "success-review-task-#{task.id}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(TASK_EVENT_TYPE, payload, delivery_id)
      log_dispatch('success_review_task_dispatched', 'TaskHub::Task', task.id, task.project_id, task.title)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::SuccessReviewDispatcher] task dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_issue_payload(issue)
      {
        event_type: ISSUE_EVENT_TYPE,
        issue_id: issue.id,
        subject: issue.subject,
        description: issue.description.to_s.truncate(2000),
        project_id: issue.project&.identifier,
        project_name: issue.project&.name,
        tracker_name: issue.tracker&.name,
        status_name: issue.status&.name,
        url: "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue.id}",
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_issue_payload

    def self.build_task_payload(task)
      {
        event_type: TASK_EVENT_TYPE,
        task_id: task.id,
        title: task.title,
        notes: task.notes.to_s.truncate(2000),
        status: task.status,
        project_id: task.project&.identifier,
        project_name: task.project&.name,
        url: build_task_url(task),
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_task_payload

    def self.build_task_url(task)
      path =
        if task.issue_id.present?
          Rails.application.routes.url_helpers.task_hub_issue_tasks_path(task)
        else
          Rails.application.routes.url_helpers.task_hub_standalone_path(task)
        end

      "#{Setting.protocol}://#{Setting.host_name}#{path}"
    rescue StandardError
      "#{Setting.protocol}://#{Setting.host_name}/task_hub/#{task.id}"
    end
    private_class_method :build_task_url

    def self.log_dispatch(action_type, target_type, target_id, project_id, summary_text)
      AutomyraBridge::ActivityLogger.log!(
        action_type: action_type,
        source: 'success_review_dispatcher',
        summary: "Success review webhook dispatched for #{target_type} ##{target_id} (#{summary_text})",
        target_type: target_type,
        target_id: target_id,
        project_id: project_id,
        user_id: nil
      )
    end
    private_class_method :log_dispatch
  end
end