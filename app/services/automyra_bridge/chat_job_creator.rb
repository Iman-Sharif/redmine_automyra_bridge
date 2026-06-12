require 'securerandom'

module AutomyraBridge
  class ChatJobCreator
    SOURCE_TYPE = 'AutomyraBridgeChatMessage'.freeze

    def self.create_job_from_message(message, thread, context)
      new.create_job_from_message(message, thread, context)
    end

    def create_job_from_message(message, thread, context)
      user = message&.user
      project = resolve_project(thread, context)
      return unless user && project
      return unless user.admin? || user.allowed_to?(:use_automyra_bridge, project)

      created = false
      job = AutomyraBridgeJob.find_or_create_by!(source_type: SOURCE_TYPE, source_id: message.id) do |record|
        created = true
        record.user = user
        record.project = project
        record.status = 'queued'
        record.correlation_id = SecureRandom.uuid
        record.idempotency_key = SecureRandom.uuid
        record.request_payload = request_payload(message, thread, context, project, user).to_json
      end

      if created
        run, run_created = create_run!(job, message, project, user, context)
        record_run_event(run, 'run.created', status: run&.status, message: 'Automyra run created.') if run_created
        record_run_event(run, 'run.queued', status: job.status, message: 'Automyra job queued.', visible_to_user: false)
        AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(thread, job)
        AutomyraBridge::AuditRecorder.record(
          'chat_job_created',
          user,
          project_id: project.id,
          message_id: message.id,
          thread_id: thread.id
        )
      end

      job
    end

    private

    def resolve_project(thread, context)
      AutomyraBridge::ChatProjectResolver.from_context(symbolized_context(context)) || thread&.project
    end

    def request_payload(message, thread, context, project, user)
      snapshot = context.is_a?(Hash) ? context[:context_snapshot] || context['context_snapshot'] : nil
      payload = {
        action: 'chat_request',
        chat_message_id: message.id,
        chat_thread_id: thread.id,
        body: message.content,
        context: context || {},
        context_snapshot: snapshot,
        channel: channel_context(thread, message),
        context_scope: context_scope(project, user)
      }.compact

      slash_command = AutomyraBridge::ChatSlashCommandParser.parse(message.content)
      tool_name = slash_command_tool_name(slash_command)
      if tool_name
        payload[:slash_command] = slash_command
        payload[:tools] = [tool_name]
        payload[:instruction_hint] = "Use the #{tool_name} tool first, then answer with the result."
      end

      payload
    end

    def slash_command_tool_name(slash_command)
      return nil unless slash_command

      case slash_command[:command]
      when 'tasks'
        %w[open mine].include?(slash_command[:args].first.to_s.downcase) ? 'task_hub.get_my_open_tasks' : nil
      when 'issues'
        slash_command[:args].first.to_s.downcase == 'mine' ? 'issues.get_my_open_issues' : nil
      when 'summarize'
        'context.current_page'
      end
    end

    def create_run!(job, message, project, user, context)
      return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists?

      run_created = false
      run = AutomyraBridgeRun.find_or_create_by!(source_type: SOURCE_TYPE, source_id: message.id) do |run|
        run_created = true
        run.user = user
        run.project = project
        run.status = run_status_for_job(job)
        run.context_snapshot = snapshot_payload(context).to_json
      end
      [run, run_created]
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridgeRun creation failed for chat message #{message&.id}: #{e.message}") if defined?(Rails)
    end

    def record_run_event(run, event_type, status: nil, message: nil, visible_to_user: true)
      return unless defined?(AutomyraBridge::RunEventRecorder)

      AutomyraBridge::RunEventRecorder.record(
        run: run,
        event_type: event_type,
        status: status,
        message: message,
        visible_to_user: visible_to_user
      )
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridgeRunEvent recording failed for #{event_type}: #{e.message}") if defined?(Rails)
      nil
    end

    def snapshot_payload(context)
      return {} unless context.is_a?(Hash)

      context[:context_snapshot] || context['context_snapshot'] || context
    end

    def run_status_for_job(job)
      job&.status == 'running' ? 'running' : 'queued'
    end

    def channel_context(thread, message)
      {
        channel: 'redmica',
        source_type: 'chat',
        source_id: thread.id,
        message_id: message.id,
        thread_id: "redmica-chat-#{thread.id}"
      }
    end

    def context_scope(project, user)
      {
        project_id: project&.id,
        source_type: SOURCE_TYPE,
        view_issues: project ? user.allowed_to?(:view_issues, project) : false,
        manage_automyra_bridge: project ? user.allowed_to?(:manage_automyra_bridge, project) : false
      }
    end

    def symbolized_context(context)
      return {} unless context.is_a?(Hash)

      context.transform_keys do |key|
        key.respond_to?(:to_sym) ? key.to_sym : key
      end
    end
  end
end
