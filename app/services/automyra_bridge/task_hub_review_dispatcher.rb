# frozen_string_literal: true

module AutomyraBridge
  # Builds and enqueues the Hermes delivery job for the
  # `redmica.task_hub.task_created` and `redmica.task_hub.task_updated` review
  # webhook events. Paired with `AutomyraBridge::TaskHubCreationHook`, which
  # is responsible for triggering this dispatcher from
  # `TaskHub::Task.after_commit`.
  #
  # The two events both target `hermes_webhook_url_task_review` (as wired up
  # in `AutomyraBridge::HermesWebhookNotifier#event_route_for`) but carry
  # distinct `event_type` values so Hermes can route them independently.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - task_created_webhook_dispatched: webhook sent to Hermes for create
  #   - task_updated_webhook_dispatched: webhook sent to Hermes for update
  class TaskHubReviewDispatcher
    EVENT_CREATED = 'redmica.task_hub.task_created'
    EVENT_UPDATED = 'redmica.task_hub.task_updated'

    LOG_CREATED = 'task_created_webhook_dispatched'
    LOG_UPDATED = 'task_updated_webhook_dispatched'

    NOTEFIELD_TRUNCATE = 2_000

    class << self
      def dispatch_created(task)
        return unless task.is_a?(::TaskHub::Task)

        delivery_id = format('task-hub-review-%<id>d-%<hex>s', id: task.id, hex: SecureRandom.hex(8))
        payload = build_payload(task, EVENT_CREATED)
        log_activity(task, LOG_CREATED)
        ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(EVENT_CREATED, payload, delivery_id)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::TaskHubReviewDispatcher] create dispatch failed: #{e.class}: #{e.message}")
      end

      def dispatch_updated(task)
        return unless task.is_a?(::TaskHub::Task)

        delivery_id = format('task-hub-review-update-%<id>d-%<hex>s', id: task.id, hex: SecureRandom.hex(8))
        payload = build_payload(task, EVENT_UPDATED)
        log_activity(task, LOG_UPDATED)
        ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(EVENT_UPDATED, payload, delivery_id)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::TaskHubReviewDispatcher] update dispatch failed: #{e.class}: #{e.message}")
      end

      # Public so tests can inspect the payload shape without re-running
      # the dispatcher side-effects. Keys are symbol keys in the dispatcher,
      # but ActiveJob stringifies Hash args during serialization, so the
      # webhook consumer (and the tests) will read them back as strings.
      def build_payload(task, event_type)
        author = resolve_user(task.author_id)
        assignee = resolve_user(task.assigned_to_id)
        project = resolve_project(task.project_id)

        {
          task_id: task.id,
          subject: task.title,
          notes: task.notes.to_s.truncate(NOTEFIELD_TRUNCATE),
          due_date: task.due_date,
          priority: task.priority,
          status: task.status,
          assigned_to_id: task.assigned_to_id,
          assigned_to_login: assignee&.login,
          parent_id: task.parent_task_id,
          project_id: project&.id,
          project_identifier: project&.identifier,
          project_name: project&.name,
          author_id: task.author_id,
          author_login: author&.login,
          tags: task.tag_list,
          checklist: serialize_checklist(task),
          url: build_task_url(task),
          timestamp: Time.current.iso8601,
          event_type: event_type
        }
      end

      private

      def resolve_user(user_id)
        return nil if user_id.blank?

        User.find_by(id: user_id)
      end

      def resolve_project(project_id)
        return nil if project_id.blank?

        Project.find_by(id: project_id)
      end

      def serialize_checklist(task)
        return [] unless task.respond_to?(:checklist_items)

        task.checklist_items.map do |item|
          {
            id: item.id,
            text: item.text,
            checked: item.checked,
            position: item.position
          }
        end
      end

      def build_task_url(task)
        path =
          if task.issue_id.present?
            Rails.application.routes.url_helpers.task_hub_issue_tasks_path(task)
          else
            Rails.application.routes.url_helpers.task_hub_standalone_path(task)
          end

        "#{Setting.protocol}://#{Setting.host_name}#{path}"
      rescue StandardError
        # Fallback when routes are not loaded (e.g. in non-Rails contexts).
        "#{Setting.protocol}://#{Setting.host_name}/task_hub/#{task.id}"
      end

      def log_activity(task, event)
        AutomyraBridge::ActivityLogger.log!(
          action_type: event,
          source: 'task_hub_creation_hook',
          summary: "Task review webhook dispatched for task ##{task.id} (#{task.title})",
          target_type: 'TaskHub::Task',
          target_id: task.id,
          project_id: task.project_id,
          user_id: task.author_id || task.user_id
        )
      end
    end
  end
end
