# frozen_string_literal: true

module AutomyraBridge
  # Creation review webhook dispatcher for Task Hub work items.
  #
  # Mirrors AutomyraBridge::CreationReviewDispatcher (which is bound to Issue),
  # but operates on TaskHub::Task and emits `redmica.task_created` so Hermes
  # can perform a deep review of the new task.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - task_creation_review_webhook_dispatched: webhook sent to Hermes
  #
  class TaskCreationReviewDispatcher
    EVENT_TYPE = 'redmica.task_created'

    def self.dispatch(task)
      return unless task.is_a?(TaskHub::Task)
      return if ENV['AUTOMYRA_BRIDGE_CREATION_REVIEW'].to_s != '1'
      return if Thread.current[:automyra_bridge_skip_webhook]

      payload = build_payload(task)
      delivery_id = "task-creation-#{task.id}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(EVENT_TYPE, payload, delivery_id)
      log_dispatch(task)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::TaskCreationReviewDispatcher] dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(task)
      {
        event_type: EVENT_TYPE,
        task_id: task.id,
        title: task.title,
        notes: task.notes.to_s.truncate(2000),
        status: task.status,
        project_id: task.project&.identifier,
        project_name: task.project&.name,
        issue_id: task.issue_id,
        author_id: task.author_id,
        author_name: task.author&.login,
        assigned_to_id: task.assigned_to_id,
        created_at: task.created_at&.iso8601,
        url: build_url(task),
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.build_url(task)
      path = if task.issue_id.blank?
               Rails.application.routes.url_helpers.task_hub_standalone_path(task)
             else
               Rails.application.routes.url_helpers.task_hub_issue_tasks_path(task)
             end
      "#{Setting.protocol}://#{Setting.host_name}#{path}"
    end
    private_class_method :build_url

    def self.log_dispatch(task)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'task_creation_review_webhook_dispatched',
        source: 'task_creation_hook',
        summary: "Creation review webhook dispatched for task ##{task.id} (#{task.title})",
        target_type: 'TaskHub::Task',
        target_id: task.id,
        project_id: task.project_id,
        user_id: task.author_id || task.user_id
      )
    end
    private_class_method :log_dispatch
  end
end
