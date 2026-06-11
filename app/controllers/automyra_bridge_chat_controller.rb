class AutomyraBridgeChatController < ApplicationController
  include ActionController::Live

  before_action :require_login
  before_action :require_valid_chat_scope
  before_action :require_automyra_chat_permission
  skip_before_action :require_valid_chat_scope, only: %i[run_events run_events_stream]
  skip_before_action :require_automyra_chat_permission, only: %i[run_events run_events_stream]

  def send_message
    content = params[:content].presence || params[:message].presence
    unless content
      render json: { success: false, error: 'No message provided' }, status: :bad_request
      return
    end

    context = chat_context
    thread = find_or_create_thread(requested_thread_kind, context)
    message = AutomyraBridge::ChatMessageCreator.create_user_message!(User.current, thread, content, context: context)

    if (local_response = local_slash_command_response(content, context))
      assistant_message = AutomyraBridge::ChatMessageCreator.create_assistant_reply!(thread, local_response, nil, context: context)
      render json: {
        success: true,
        message: message_json(message),
        user_message: message_json(message),
        assistant_placeholder: message_json(assistant_message),
        thread_id: thread.id,
        thread_kind: thread.thread_kind
      }
      return
    end

    job = AutomyraBridge::ChatJobCreator.create_job_from_message(message, thread, context)

    unless job
      render json: {
        success: false,
        error: 'Automyra could not be started for the current page context.'
      }, status: :unprocessable_entity
      return
    end

    assistant_placeholder = assistant_placeholder_for(thread, job, context)

    run = automyra_run_for_message(message)

    render json: {
      success: true,
      message: message_json(message),
      user_message: message_json(message),
      assistant_placeholder: message_json(assistant_placeholder),
      thread_id: thread.id,
      thread_kind: thread.thread_kind,
      run_id: run&.id,
      job_id: job.id,
      job: safe_job_summary(job)
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def history
    thread = authorized_thread || find_thread(requested_thread_kind)

    unless thread
      render json: { messages: [] }
      return
    end

    messages = thread.chat_messages.order(created_at: :desc).limit(50).reverse
    render json: { messages: messages.map { |message| message_json(message) }, thread_id: thread.id }
  end

  def poll
    thread = authorized_thread || find_thread(requested_thread_kind)
    result = AutomyraBridge::ChatPollService.poll(
      thread,
      since_message_id: params[:last_message_id],
      since_updated_at: params[:last_seen_update_at]
    )

    messages = result[:new_messages].first(50)

    render json: {
      messages: messages_with_job_summaries(thread, messages),
      jobs: job_summaries_for_thread(thread),
      unread_count: result[:unread_count],
      has_updates: result[:has_updates],
      thread_status: result[:thread_status],
      last_message_id: result[:last_message_id],
      last_seen_update_at: result[:last_seen_update_at],
      server_time: result[:server_time]
    }
  end

  def run_events
    run = AutomyraBridgeRun.find_by(id: params[:id])
    unless run
      render json: { error: 'Run not found' }, status: :not_found
      return
    end

    unless authorized_to_view_run_events?(run)
      render json: { error: 'Access denied' }, status: :forbidden
      return
    end

    unless AutomyraBridge::RunEventRecorder.available?
      render json: { run_id: run.id, run_status: run.status, events: [], warning: 'Run events are unavailable because the plugin migration has not been applied.' }
      return
    end

    events = run.run_events
    events = events.visible unless can_view_private_run_events?(run)
    events = events.where('id > ?', params[:after_id].to_i) if params[:after_id].present?
    events = events.order(:id)

    render json: {
      run_id: run.id,
      run_status: run.status,
      events: events.map { |event| run_event_json(event) }
    }
  end

  def run_events_stream
    run = AutomyraBridgeRun.find_by(id: params[:id])
    unless run
      render json: { error: 'Run not found' }, status: :not_found
      return
    end

    unless authorized_to_view_run_events?(run)
      render json: { error: 'Access denied' }, status: :forbidden
      return
    end

    unless AutomyraBridge::RunEventRecorder.available?
      render json: { error: 'Run events unavailable' }, status: :service_unavailable
      return
    end

    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'

    stream_run_events(run)
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client closed the browser tab or EventSource connection.
  rescue StandardError => e
    write_sse_error(e)
  ensure
    begin
      response.stream.close
    rescue IOError, ActionController::Live::ClientDisconnected
      nil
    end
  end

  def toggle_thread
    new_kind = requested_thread_kind
    current_context = page_context

    if new_kind == 'global'
      result = AutomyraBridge::ChatThreadToggle.switch_to_global(User.current, project_id: current_context[:project_id])
    else
      result = AutomyraBridge::ChatThreadToggle.switch_to_page(
        User.current,
        current_context[:page_type],
        current_context[:page_id],
        project_id: current_context[:project_id],
        url_path: current_context[:url_path]
      )
    end
    thread = result.thread

    render json: {
      thread_id: thread.id,
      thread_kind: thread.thread_kind,
      messages: thread.chat_messages.order(:created_at).limit(50).map { |message| message_json(message) },
      unread_count: thread.unread_count
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def mark_read
    return render json: { success: false, error: 'thread_id is required' }, status: :bad_request if params[:thread_id].blank?

    thread = authorized_thread
    return render json: { success: false, error: 'Thread not found' }, status: :not_found unless thread

    thread.mark_read!
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Thread not found' }, status: :not_found
  end

  def upload_attachment
    return render json: { error: 'No file provided' }, status: :bad_request unless params[:file].present?

    context = chat_context
    thread = authorized_thread || find_or_create_thread(requested_thread_kind, context)
    return head :forbidden unless AutomyraBridge::ChatPermission.allowed?(User.current, thread: thread)
    message = if params[:message_id].present?
                thread.chat_messages.find_by(id: params[:message_id])
              else
                AutomyraBridge::ChatMessageCreator.create_user_message!(User.current, thread, params[:content].presence || '', context: context)
              end
    return head :not_found unless message

    attachment = Attachment.create!(
      file: params[:file],
      author: User.current,
      container: message
    )
    render json: {
      attachment: {
        id: attachment.id,
        filename: attachment.filename,
        url: attachment_path(attachment),
        content_type: attachment.content_type,
        filesize: attachment.filesize
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def retry_job
    job = AutomyraBridgeJob.find_by(id: params[:job_id])
    unless job
      render json: { error: 'Job not found' }, status: :not_found
      return
    end

    unless authorized_to_retry?(job)
      render json: { error: 'Access denied' }, status: :forbidden
      return
    end

    unless %w[failed queued max_steps_reached].include?(job.status)
      render json: { error: 'Job cannot be retried' }, status: :unprocessable_entity
      return
    end

    reset_failed_job(job)
    record_job_run_event(job, 'run.retried', status: job.status, message: 'Automyra run retried.', user: User.current)
    run = AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id) if defined?(AutomyraBridgeRun)
    render json: { success: true, job_id: job.id, status: job.status, run_id: run&.id, run_status: run&.status }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def cancel_job
    job = AutomyraBridgeJob.find_by(id: params[:job_id])
    unless job
      render json: { error: 'Job not found' }, status: :not_found
      return
    end

    unless authorized_to_retry?(job)
      render json: { error: 'Access denied' }, status: :forbidden
      return
    end

    unless %w[queued running retrying failed max_steps_reached].include?(job.status)
      render json: { error: 'Job cannot be cancelled' }, status: :unprocessable_entity
      return
    end

    job.update!(status: 'cancelled', error_message: 'Cancelled by user.', finished_at: Time.current)
    record_job_run_event(job, 'run.cancelled', status: job.status, message: 'Automyra run cancelled.', user: User.current)
    placeholder = AutomyraBridgeChatMessage.where(job_id: job.id, role: 'assistant').order(:id).last
    placeholder&.update_columns(status: 'failed', content: 'Automyra run cancelled.', updated_at: Time.current)
    run = AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id) if defined?(AutomyraBridgeRun)
    render json: { success: true, job_id: job.id, status: job.status, run_id: run&.id, run_status: run&.status }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def new_thread
    context = chat_context
    thread = find_or_create_thread(requested_thread_kind, context)
    thread.chat_messages.create!(user: User.current, role: 'system', kind: (AutomyraBridgeChatMessage.column_names.include?('kind') ? 'summary' : 'message'), status: 'delivered', content: 'New thread started.')
    render json: { success: true, thread_id: thread.id, thread_kind: thread.thread_kind, messages: thread.chat_messages.order(:created_at).limit(50).map { |message| message_json(message) } }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def require_automyra_chat_permission
    allowed = if authorized_thread
                AutomyraBridge::ChatPermission.allowed?(User.current, thread: authorized_thread)
              elsif params[:thread_id].present?
                false
              elsif resolved_project && !AutomyraBridge::ChatProjectResolver.visible_to_user?(User.current, resolved_project)
                false
              else
                AutomyraBridge::ChatPermission.allowed?(User.current, project: resolved_project, page_type: page_context[:page_type], page_id: page_context[:page_id])
              end

    unless allowed
      render json: { success: false, error: 'Access denied' }, status: :forbidden
    end
  end

  def require_valid_chat_scope
    unless AutomyraBridge::ChatPermission.valid_thread_kind?(requested_thread_kind)
      render json: { success: false, error: 'Invalid thread kind' }, status: :bad_request
      return
    end

    if requested_thread_kind == 'page' && params[:thread_id].blank? && !AutomyraBridge::ChatPermission.valid_page_type?(page_context[:page_type])
      render json: { success: false, error: 'Invalid page type' }, status: :bad_request
    end
  end

  def find_thread(kind)
    if kind == 'global'
      AutomyraBridgeChatThread.global_for(User.current).first
    else
      context = page_context
      AutomyraBridgeChatThread.for_page(User.current, context[:page_type], context[:page_id], project_id: context[:project_id], url_path: context[:url_path]).first
    end
  end

  def find_or_create_thread(kind, context)
    if kind == 'global'
      AutomyraBridge::ChatThreadToggle.switch_to_global(User.current, project_id: context[:project_id]).thread
    else
      AutomyraBridge::ChatThreadToggle.switch_to_page(
        User.current,
        context[:page_type],
        context[:page_id],
        project_id: context[:project_id],
        url_path: context[:url_path]
      ).thread
    end
  end

  def chat_context
    context = AutomyraBridge::ChatContextBuilder.from_controller(self).merge(explicit_page_context).merge(
      thread_kind: requested_thread_kind,
      project_id: resolved_project&.id
    )
    context.merge(context_snapshot: context_snapshot(context))
  end

  def explicit_page_context
    page_context.reject { |_key, value| value.blank? }
  end

  def local_slash_command_response(content, context)
    slash_command = AutomyraBridge::ChatSlashCommandParser.parse(content)
    return nil unless slash_command

    case slash_command[:command]
    when 'help'
      slash_help_text
    when 'page'
      slash_page_text(context)
    end
  end

  def slash_help_text
    [
      'Available slash commands:',
      '/help - Show this help.',
      '/page - Show the current page context.',
      '/tasks open - List your open tasks.',
      '/tasks mine - List your open tasks.',
      '/issues mine - List your open issues.',
      '/summarize - Summarize the current page.'
    ].join("\n")
  end

  def slash_page_text(context)
    snapshot = context[:context_snapshot] || context['context_snapshot'] || {}
    page = snapshot[:page] || snapshot['page'] || {}
    lines = ['Current page context:']
    lines << "Title: #{page[:title] || page['title'] || context[:page_title] || context['page_title'] || '(none)'}"
    lines << "URL: #{page[:url] || page['url'] || context[:url_path] || context['url_path'] || '(none)'}"
    lines << "Type: #{page[:type] || page['type'] || context[:page_type] || context['page_type'] || '(none)'}"
    lines << "ID: #{page[:id] || page['id'] || context[:page_id] || context['page_id'] || '(none)'}"
    lines.join("\n")
  end

  def message_json(message)
    json = {
      id: message.id,
      role: message.role,
      content: message.content,
      status: message.status,
      job_id: message.job_id,
      created_at: message.created_at.iso8601,
      updated_at: message.updated_at.utc.iso8601(3),
      has_proposal: message.has_proposal?,
      proposal_id: message.proposal_id
    }
    json[:user_name] = message.user&.name if message.respond_to?(:user) && message.user
    json[:kind] = message.kind if message.respond_to?(:kind)
    sources = sources_for_message(message)
    json[:sources] = sources if sources.present?
    job = job_summary_for_message(message)
    json[:job] = job if job
    json
  end

  def assistant_placeholder_for(thread, job, context)
    AutomyraBridgeChatMessage.where(chat_thread: thread, job_id: job.id, role: 'assistant').order(:id).last ||
      AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(thread, job, context: context)
  end

  def safe_job_summary(job)
    summary = { id: job.id }
    summary[:status] = job.status if job.respond_to?(:status)
    summary[:retry_count] = job.retry_count if job_column?(job, :retry_count)
    summary[:max_retries] = job.max_retries if job_column?(job, :max_retries)
    summary[:backoff_seconds] = job.backoff_seconds if job_column?(job, :backoff_seconds)
    summary[:last_heartbeat_at] = job.last_heartbeat_at&.utc&.iso8601 if job_column?(job, :last_heartbeat_at)
    summary[:next_retry_at] = next_retry_at_for(job)
    summary[:error_summary] = sanitized_error_summary(job.error_message) if job_column?(job, :error_message)
    summary
  end

  def job_summary_for_message(chat_message)
    return nil unless chat_message&.job_id.present?
    return nil unless AutomyraBridge::ChatPermission.allowed?(User.current, thread: chat_message.chat_thread)

    job = AutomyraBridgeJob.find_by(id: chat_message.job_id)
    safe_job_summary(job) if job
  end

  def job_summaries_for_thread(thread)
    return [] unless thread && AutomyraBridge::ChatPermission.allowed?(User.current, thread: thread)

    messages = thread.chat_messages.where(role: 'assistant').where.not(job_id: nil).order(created_at: :desc, id: :desc).limit(20)
    messages.filter_map { |message| job_summary_for_message(message) }.uniq { |job| job[:id] }
  end

  def run_event_json(event)
    payload = proposal_event_payload(event) || event.payload
    {
      id: event.id,
      event_type: event.event_type,
      status: event.status,
      message: event.message,
      payload: payload,
      sources: event_sources(event, payload),
      visible_to_user: event.visible_to_user,
      created_at: event.created_at.utc.iso8601(3)
    }
  end

  def event_sources(event, payload)
    parsed = payload.is_a?(Hash) ? payload : JSON.parse(payload.to_s.presence || '{}')
    raw = parsed['sources'] || parsed[:sources] || parsed['sources_used'] || parsed[:sources_used]
    run_id = event.respond_to?(:automyra_bridge_run_id) ? event.automyra_bridge_run_id : event.run&.id
    return raw if raw.is_a?(Array)
    return [] unless raw.is_a?(Hash)

    [
      *Array(raw['tools'] || raw[:tools]).map { |name| { type: 'tool', name: name } },
      ({ type: 'page_context', context: raw['page_context'] || raw[:page_context] } if (raw['page_context'] || raw[:page_context]).present?),
      *Array(raw['memory_events'] || raw[:memory_events]).map { |id| { type: 'memory_event', id: id } },
      *memory_event_sources_for_run(run_id)
    ].compact
  rescue JSON::ParserError
    []
  end

  def memory_event_sources_for_run(run_id)
    return [] unless run_id && defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?

    AutomyraBridgeMemoryEvent.where(run_id: run_id).limit(10).map { |memory| { type: 'memory_event', id: memory.id, event_type: memory.event_type } }
  rescue StandardError
    []
  end

  def proposal_event_payload(event)
    return nil unless event.event_type.to_s.start_with?('action_proposal.') || event.event_type.to_s.start_with?('proposal.')

    payload = event.payload.is_a?(Hash) ? event.payload.deep_dup : JSON.parse(event.payload.to_s.presence || '{}')
    proposal = AutomyraBridgeActionProposal.find_by(id: payload['proposal_id'] || payload[:proposal_id])
    return payload unless proposal

    risk_level = proposal_risk_level(proposal)
    payload.merge(
      proposal_id: proposal.id,
      action_type: proposal.action_type,
      target_type: proposal.target_type,
      target_id: proposal.target_id,
      risk_level: risk_level,
      reason: proposal_approval_reason(risk_level),
      status: proposal.status,
      can_manage: can_manage_proposal?(proposal),
      result: proposal_result_payload(proposal)
    ).compact
  rescue JSON::ParserError
    event.payload
  end

  def proposal_risk_level(proposal)
    AutomyraBridge::ToolRegistry.find_by_legacy_action(proposal.action_type)&.risk_level.presence || 'write'
  end

  def proposal_approval_reason(risk_level)
    return 'This read-only action is being shown for review before Automyra continues.' if risk_level == 'read'

    'This action can modify Redmica data and requires operator approval.'
  end

  def can_manage_proposal?(proposal)
    User.current&.admin? || User.current&.allowed_to?(:manage_automyra_bridge, proposal.project)
  end

  def proposal_result_payload(proposal)
    JSON.parse(proposal.result_payload.to_s.presence || '{}')
  rescue JSON::ParserError
    proposal.result_payload
  end

  def sources_for_message(message)
    return nil unless message&.role == 'assistant' && message.job_id.present?
    return nil unless AutomyraBridge::RunEventRecorder.available?

    run = AutomyraBridgeRun.find_by(source_type: 'AutomyraBridgeChatMessage', source_id: message.job&.source_id || message.id) if defined?(AutomyraBridgeRun)
    payload = run&.run_events&.where(event_type: 'run.completed')&.order(:id)&.last&.payload
    parsed = payload.is_a?(Hash) ? payload : JSON.parse(payload.to_s.presence || '{}')
    sources = parsed['sources'] || parsed[:sources] || parsed['sources_used'] || parsed[:sources_used]
    sources.presence
  rescue StandardError
    nil
  end

  def stream_run_events(run)
    last_event_id = request.headers['Last-Event-ID'].presence || params[:last_event_id].presence
    after_id = last_event_id.to_i
    heartbeat_at = Time.current

    loop do
      begin
        events = run_events_scope(run).where('id > ?', after_id).order(:id).limit(100)
        events.each do |event|
          response.stream.write("data: #{run_event_json(event).to_json}\n\n")
          after_id = event.id
        end

        run.reload
        break if run_terminal?(run) && !run_events_scope(run).where('id > ?', after_id).exists?

        if heartbeat_at <= 25.seconds.ago
          response.stream.write(": heartbeat\n\n")
          heartbeat_at = Time.current
        end

        sleep 1
      rescue ActiveRecord::ActiveRecordError => e
        response.stream.write("event: error\n")
        response.stream.write("data: #{ { error: 'Database unavailable', message: e.message }.to_json }\n\n")
        break
      end
    end
  end

  def run_events_scope(run)
    return AutomyraBridgeRunEvent.none unless AutomyraBridge::RunEventRecorder.available?

    events = run.run_events
    events = events.visible unless can_view_private_run_events?(run)
    events
  end

  def run_terminal?(run)
    %w[completed failed cancelled].include?(run.status.to_s)
  end

  def write_sse_error(error)
    Rails.logger.warn("AutomyraBridge SSE stream failed: #{error.class}: #{error.message}") if defined?(Rails)

    response.stream.write("event: error\n")
    response.stream.write("data: #{ { error: 'SSE stream unavailable' }.to_json }\n\n")
  rescue IOError, ActionController::Live::ClientDisconnected
    nil
  end

  def automyra_run_for_message(message)
    return unless defined?(AutomyraBridgeRun) && message

    AutomyraBridgeRun.find_by(source_type: AutomyraBridge::ChatJobCreator::SOURCE_TYPE, source_id: message.id)
  rescue StandardError
    nil
  end

  def authorized_to_view_run_events?(run)
    return false unless User.current
    return true if run.user_id == User.current.id

    User.current.allowed_to?(:view_automyra_bridge_chat, run.project) ||
      User.current.allowed_to?(:manage_automyra_bridge, run.project)
  end

  def can_view_private_run_events?(run)
    User.current.admin? || run.user_id == User.current.id
  end

  def messages_with_job_summaries(thread, message_hashes)
    return message_hashes if thread.nil? || message_hashes.blank?

    messages_by_id = thread.chat_messages.where(id: message_hashes.map { |message| message[:id] }).index_by(&:id)

    message_hashes.map do |message_hash|
      message_json = message_hash.dup
      message = messages_by_id[message_hash[:id]]
      job = job_summary_for_message(message)
      message_json[:job] = job if job
      message_json
    end
  end

  def next_retry_at_for(job)
    return nil unless job_column?(job, :backoff_seconds) && job.backoff_seconds.to_i.positive?

    (job.updated_at + job.backoff_seconds.to_i.seconds).utc.iso8601
  end

  def sanitized_error_summary(raw_message)
    message = raw_message.to_s
    return nil if message.blank?

    sanitized = message.lines.reject { |line| stack_trace_line?(line) }.join(' ')
    sanitized.gsub!(/https?:\/\/\S+/i, '[url]')
    sanitized.gsub!(/\b(?:[a-z0-9-]+\.)+(?:local|internal|localhost|lan|test|invalid)\b/i, '[host]')
    sanitized.gsub!(/\b(?:localhost|127\.0\.0\.1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b/i, '[host]')
    sanitized.gsub!(/\b(?:token|api[_-]?key|secret|password|authorization|bearer)\b\s*[:=]\s*\S+/i, '\\1=[redacted]')
    sanitized.gsub!(/\bBearer\s+\S+/i, 'Bearer [redacted]')
    sanitized.gsub!(/\b[A-Za-z0-9_\-.]{32,}\b/, '[redacted]')
    sanitized.squish.truncate(250)
  end

  def stack_trace_line?(line)
    line.match?(/\.rb:\d+:in\s/) || line.match?(/^\s*from\s+.+:\d+/) || line.match?(/^\s*\/[^\s]+:\d+/)
  end

  def job_column?(job, column_name)
    job.respond_to?(column_name) && job.class.column_names.include?(column_name.to_s)
  end

  def page_context
    canonical_page_type = params[:page_type].present? ? AutomyraBridge::ChatContextSnapshotBuilder.normalize_page_type(params[:page_type]) : ''
    {
      page_type: canonical_page_type,
      page_id: params[:page_id].presence || '',
      project_id: resolved_project&.id,
      url_path: params[:url_path].presence,
      page_title: params[:page_title].presence,
      issue_id: canonical_page_type == 'issue' ? params[:page_id].presence : nil,
      wiki_page_title: params[:wiki_page_title].presence,
      task_id: canonical_page_type == 'task_hub_task' ? params[:page_id].presence : nil
    }
  end

  def context_snapshot(context)
    snapshot = AutomyraBridge::ChatContextSnapshotBuilder.build(
      user: User.current,
      page_type: context[:page_type],
      page_id: context[:page_id],
      project_id: context[:project_id],
      url_path: context[:url_path],
      page_title: context[:page_title]
    )
    attachment = safe_attachment_context(params[:file]) if params[:file].present?
    attachment ? snapshot.merge(attachment: attachment) : snapshot
  end

  def safe_attachment_context(file)
    metadata = { filename: file.original_filename.to_s, content_type: file.content_type.to_s, filesize: file.size.to_i }
    return metadata unless allowlisted_attachment?(metadata)

    text = if metadata[:content_type] == 'application/pdf'
             ''
           else
             file.tempfile.rewind
             file.tempfile.read.to_s.encode('UTF-8', invalid: :replace, undef: :replace).truncate(4000)
           end
    metadata.merge(text: text.presence).compact
  rescue StandardError
    metadata
  end

  def allowlisted_attachment?(metadata)
    metadata[:filesize].to_i <= 1.megabyte && (
      metadata[:content_type].to_s.start_with?('text/') ||
      %w[application/json application/xml application/pdf].include?(metadata[:content_type].to_s)
    )
  end

  def requested_thread_kind
    params[:thread_kind].presence || (raw_page_type.present? || raw_page_id.present? ? 'page' : 'global')
  end

  def resolved_project
    @resolved_project ||= AutomyraBridge::ChatProjectResolver.from_page(raw_page_type, raw_page_id) ||
                          AutomyraBridge::ChatProjectResolver.from_project_id(params[:project_id])
  end

  def authorized_thread
    return nil if params[:thread_id].blank?
    @authorized_thread ||= AutomyraBridgeChatThread.where(user: User.current).find_by(id: params[:thread_id])
  end

  def raw_page_type
    params[:page_type].presence || ''
  end

  def raw_page_id
    params[:page_id].presence || ''
  end

  def authorized_to_retry?(job)
    return false unless User.current

    if job.source_type == 'AutomyraBridgeChatMessage'
      placeholder = AutomyraBridgeChatMessage.where(job_id: job.id).first
      if placeholder
        return AutomyraBridge::ChatPermission.allowed?(User.current, thread: placeholder.chat_thread)
      end
    end

    project = job.project
    project && (User.current.admin? || User.current.allowed_to?(:use_automyra_bridge, project))
  end

  def reset_failed_job(job)
    AutomyraBridgeJob.where(id: job.id, status: job.status)
                     .update_all(
                       status: 'queued',
                        retry_count: (job.retry_count.to_i + 1).clamp(0, job.max_retries.to_i),
                       error_message: nil,
                       backoff_seconds: 0,
                       started_at: nil,
                       finished_at: nil,
                       last_heartbeat_at: nil,
                       updated_at: Time.current
                     )
    job.reload

    placeholder = AutomyraBridgeChatMessage.where(job_id: job.id, role: 'assistant').order(:id).last
    placeholder&.update_columns(
      content: '',
      status: 'pending',
      proposal_id: nil,
      updated_at: Time.current
    )
  end

  def record_job_run_event(job, event_type, status:, message:, user: nil)
    return unless defined?(AutomyraBridge::RunEventRecorder)
    return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists?

    run = AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id)
    return unless run

    run.update!(status: status) if run.status != status && AutomyraBridgeRun::STATUSES.include?(status)
    AutomyraBridge::RunEventRecorder.record(
      run: run,
      event_type: event_type,
      status: status,
      message: message,
      payload: { job_id: job.id, status: status, changed_at: Time.current.utc.iso8601(3) },
      visible_to_user: true,
      created_by: user
    )
  rescue StandardError => e
    Rails.logger.warn("Automyra chat job run event failed for job #{job&.id}: #{e.message}") if defined?(Rails)
  end
end
