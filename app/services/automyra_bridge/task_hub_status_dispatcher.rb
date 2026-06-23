# frozen_string_literal: true

module AutomyraBridge
  # Task Hub status-change webhook dispatcher.
  #
  # Dispatches Task Hub status-change events to Hermes so the `task-review`
  # skill can re-evaluate standards when a task moves between statuses
  # (e.g. todo -> in_progress -> done).
  #
  # Mirrors AutomyraBridge::TaskHubReviewDispatcher (create/update) but emits
  # `redmica.task_hub.task_status_changed` with a compact status payload.
  class TaskHubStatusDispatcher
    STATUS_EVENT_TYPE = 'redmica.task_hub.task_status_changed'

    def self.dispatch(task)
      return unless task.is_a?(::TaskHub::Task)

      payload = build_payload(task)
      delivery_id = "task-hub-review-status-#{task.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(STATUS_EVENT_TYPE, payload, delivery_id)
      log_dispatch(task)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::TaskHubStatusDispatcher] status dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(task)
      project = task.project
      author = task.author
      {
        event_type: STATUS_EVENT_TYPE,
        task_id: task.id,
        subject: task.title,
        new_status: task.status,
        old_status: task.status_before_last_save,
        priority: task.priority,
        assigned_to_id: task.assigned_to_id,
        project_id: project&.id,
        project_identifier: project&.identifier,
        project_name: project&.name,
        author_id: task.author_id,
        author_login: author&.login,
        url: build_url(task),
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.build_url(task)
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
    private_class_method :build_url

    def self.log_dispatch(task)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'task_status_changed_webhook_dispatched',
        source: 'task_hub_status_hook',
        summary: "Task status review webhook dispatched for task ##{task.id} (#{task.title})",
        target_type: 'TaskHub::Task',
        target_id: task.id,
        project_id: task.project_id,
        user_id: task.author_id || task.user_id
      )
    end
    private_class_method :log_dispatch
  end
end
