require 'securerandom'
require 'zlib'
require 'json'

module AutomyraBridge
  class JobCreator
    def self.create_for_task_comment(comment)
      return unless defined?(TaskHub::TaskComment)
      return unless comment.is_a?(TaskHub::TaskComment)
      return unless MentionDetector.mentioned?(comment.body)

      task = comment.task
      project = task.project || task.issue&.project
      payload = {
        action: 'mention_response',
        source: 'task_hub_comment',
        comment_id: comment.id,
        task_id: task.id,
        task_title: task.title,
        task_notes: task.notes,
        issue_id: task.issue_id,
        body: comment.body,
        context_scope: context_scope(comment.author, project, task),
        channel: channel_context('task', task.id, comment.id),
        context: AutomyraBridge::ContextBuilder.for_task(task, comment.author)
      }
      return unless comment.author && project
      return unless comment.author.admin? || comment.author.allowed_to?(:use_automyra_bridge, project)

      cancel_pending_retries('TaskHub::Task', task.id)

      if handle_mentions?
        correlation_id = SecureRandom.uuid
        idempotency_key = SecureRandom.uuid
        payload[:correlation_id] = correlation_id
        payload[:idempotency_key] = idempotency_key

        ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(
          'redmica.task_comment_mention', payload, "task-comment-#{comment.id}"
        )

        AutomyraBridge::ActivityLogger.log!(
          action_type: 'mention_response',
          source: 'bridge_webhook',
          summary: "Mention detected on Task ##{task.id}",
          session_id: correlation_id,
          target_type: 'TaskHub::Task',
          target_id: task.id,
          project_id: project&.id,
          user_id: comment.author&.id
        )
        true
      else
        job = create_job(source_type: 'TaskHub::TaskComment', source_id: comment.id,
                         user: comment.author, project: project, payload: payload)
        write_mention_memory(task, comment.author, comment.body, job, comment.id) if job
        if job
          enqueue_hermes_webhook(event_type: 'redmica.task_comment_mention', job: job,
                                 delivery_id: "task-comment-#{comment.id}")
        end
        if job
          AutomyraBridge::ActivityLogger.log!(
            action_type: 'mention_response',
            source: 'bridge_webhook',
            summary: "Mention detected on Task ##{task.id}",
            session_id: job.correlation_id,
            target_type: 'TaskHub::Task',
            target_id: task.id,
            project_id: project&.id,
            user_id: comment.author&.id
          )
        end
        job
      end
    end

    def self.create_for_issue_journal(journal)
      return unless journal.is_a?(Journal)
      return unless journal.journalized.is_a?(Issue)
      return unless MentionDetector.mentioned?(journal.notes)
      return if bridge_generated?(journal.notes)

      issue = journal.journalized
      payload = {
        action: 'mention_response',
        source: 'issue_journal',
        journal_id: journal.id,
        issue_id: issue.id,
        issue_subject: issue.subject,
        body: journal.notes,
        context_scope: context_scope(journal.user, issue.project, issue),
        channel: channel_context('issue', issue.id, journal.id),
        context: AutomyraBridge::ContextBuilder.for_issue(issue, journal.user)
      }
      return unless journal.user && issue.project
      return unless journal.user.admin? || journal.user.allowed_to?(:use_automyra_bridge, issue.project)

      cancel_pending_retries('Issue', issue.id)

      if handle_mentions?
        correlation_id = SecureRandom.uuid
        idempotency_key = SecureRandom.uuid
        payload[:correlation_id] = correlation_id
        payload[:idempotency_key] = idempotency_key

        ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(
          'redmica.issue_mention', payload, "issue-journal-#{journal.id}"
        )

        AutomyraBridge::ActivityLogger.log!(
          action_type: 'mention_response',
          source: 'bridge_webhook',
          summary: "Mention detected on Issue ##{issue.id}",
          session_id: correlation_id,
          target_type: 'Issue',
          target_id: issue.id,
          project_id: issue.project_id,
          user_id: journal.user_id
        )
        true
      else
        job = create_job(source_type: 'Journal', source_id: journal.id,
                         user: journal.user, project: issue.project, payload: payload)
        write_mention_memory(issue, journal.user, journal.notes, job, journal.id) if job
        if job
          enqueue_hermes_webhook(event_type: 'redmica.issue_mention', job: job,
                                 delivery_id: "issue-journal-#{journal.id}")
        end
        if job
          AutomyraBridge::ActivityLogger.log!(
            action_type: 'mention_response',
            source: 'bridge_webhook',
            summary: "Mention detected on Issue ##{issue.id}",
            session_id: job.correlation_id,
            target_type: 'Issue',
            target_id: issue.id,
            project_id: issue.project_id,
            user_id: journal.user_id
          )
        end
        job
      end
    end

    def self.create_for_webhook(user:, project:, payload:, source_id: nil)
      normalized = payload.deep_stringify_keys
      create_job(
        source_type: 'WebhookIncoming',
        source_id: source_id || Zlib.crc32(normalized.to_json),
        user: user,
        project: project,
        payload: {
          action: 'email_ingestion',
          source: normalized['source'].presence || 'outlook',
          destination: normalized['destination'].presence || normalized['action'].presence || 'ask',
          subject: normalized['subject'],
          from: normalized['from'],
          sender: normalized['sender'],
          sent_at: normalized['sent_at'].presence || normalized['date'],
          body: normalized['body'],
          html_body: normalized['html_body'],
          attachments: Array(normalized['attachments']),
          context_scope: context_scope(user, project, project),
          channel: channel_context('webhook_email', source_id || Zlib.crc32(normalized.to_json), normalized['message_id'])
        }
      )
    end

    def self.create_job(source_type:, source_id:, user:, project:, payload:)
      return unless user && project
      return unless user.admin? || user.allowed_to?(:use_automyra_bridge, project)

      AutomyraBridgeJob.find_or_create_by!(source_type: source_type, source_id: source_id) do |job|
        job.user = user
        job.project = project
        job.status = 'queued'
        job.correlation_id = SecureRandom.uuid
        job.idempotency_key = SecureRandom.uuid
        job.request_payload = payload.to_json
      end
    end

    def self.bridge_generated?(text)
      text.to_s.include?(AutomyraBridge::JobProcessor::STATUS_MARKER)
    end

    def self.cancel_pending_retries(target_type, target_id)
      AutomyraBridgeWebhookDelivery.for_target(target_type, target_id).pending.update_all(status: 'cancelled', updated_at: Time.current)
    rescue StandardError => e
      Rails.logger.warn("[AutomyraBridge::JobCreator] failed to cancel pending retries: #{e.class}: #{e.message}")
    end

    def self.handle_mentions?
      ENV['AUTOMYRA_BRIDGE_HANDLE_MENTIONS'].to_s == '1'
    end

    def self.enqueue_hermes_webhook(event_type:, job:, delivery_id:)
      return unless job

      payload = JSON.parse(job.request_payload || '{}')
      payload['job_id'] = job.id
      payload['correlation_id'] = job.correlation_id
      payload['idempotency_key'] = job.idempotency_key

      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(event_type, payload, delivery_id)
    rescue StandardError => e
      Rails.logger.warn("[AutomyraBridge::JobCreator] failed to enqueue Hermes webhook: #{e.class}: #{e.message}")
    end

    def self.context_scope(user, project, source)
      {
        project_id: project.id,
        source_type: source.class.name,
        view_issues: user.allowed_to?(:view_issues, project),
        view_task_hub_tasks: user.allowed_to?(:view_task_hub_tasks, project),
        edit_task_hub_tasks: user.allowed_to?(:manage_task_hub_tasks, project),
        manage_automyra_bridge: user.allowed_to?(:manage_automyra_bridge, project)
      }
    end

    def self.channel_context(kind, source_id, message_id)
      {
        channel: 'redmica',
        source_type: kind,
        source_id: source_id,
        message_id: message_id,
        thread_id: "redmica-#{kind}-#{source_id}"
      }
    end

    def self.write_mention_memory(container, user, content, job, journal_id)
      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: user,
        role: 'user',
        event_type: 'user_mention',
        content: content,
        payload: job.payload,
        correlation_id: job.correlation_id,
        journal_id: journal_id
      )
    end
  end
end
