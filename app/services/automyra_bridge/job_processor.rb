require 'net/http'
require 'json'

module AutomyraBridge
  class JobProcessor
    STATUS_MARKER = '<!-- automyra-bridge-status -->'.freeze

    def self.process_single_job(job = nil)
      job ||= AutomyraBridgeJob.ready_to_process.order(:created_at, :id).first
      new.process(job) if job
    end

    class AdapterResponseError < StandardError
      attr_reader :error_code, :error_summary

      def initialize(error_code, error_summary)
        @error_code = error_code.to_s.presence || 'adapter_error'
        @error_summary = error_summary.to_s.presence || 'Automyra adapter request failed.'
        super([@error_code, @error_summary].compact.join(': '))
      end
    end

    def initialize(settings = Setting.plugin_redmine_automyra_bridge)
      @settings = settings || {}
    end

    def process(job)
      return unless claim(job)

      mark_run_running(job)
      heartbeat!(job)
      @outbound_payload = payload(job)
      write_outbound_memory(job, @outbound_payload)
      heartbeat!(job)
      return AutomyraBridge::AssistantRunProcessor.new(job_processor: self, settings: @settings).process(job, @outbound_payload) if chat_job?(job)

      response = post_payload(job)
      heartbeat!(job)
      parsed = parse_response(response.body)
      message = response_text(parsed)
      return job if cancelled?(job)

      write_model_response_memory(job, parsed)
      proposals = AutomyraBridge::ActionProposalCreator.create_from_response(job, parsed)
      write_assistant_memory(job, message, parsed, proposals)
      heartbeat!(job)
      update_chat_assistant_message(job, message, proposals) if chat_job?(job)
      execute_autonomous_proposals(job, proposals)
      mark_run_completed(job, parsed, proposals)
      job.update!(status: 'succeeded', response_payload: parsed.to_json, error_message: nil, backoff_seconds: 0, finished_at: Time.current, last_heartbeat_at: Time.current)
      safely_post_status(job, status_body(message)) unless chat_job?(job)
      job
    rescue StandardError => e
      handle_failure(job, e) if job
      job
    end

    def recover_stale!(job)
      return unless job&.status == 'running' && stale?(job)

      if job.retryable?
        job.increment_retry!
        job.update!(status: 'pending', error_message: 'Automyra job was interrupted while running.', started_at: nil, finished_at: nil, last_heartbeat_at: nil, updated_at: job.backoff_seconds.seconds.from_now)
        mark_run_retrying(job)
      else
        mark_failed!(job, 'Automyra job was interrupted while running.')
      end
    end

    private

    def status_body(message)
      "#{STATUS_MARKER}\n#{message}"
    end

    def claim(job)
      return false unless job && %w[queued pending].include?(job.status)
      return false if job.backoff_seconds.to_i.positive? && job.updated_at && job.updated_at > Time.current

      claimed = AutomyraBridgeJob.where(id: job.id, status: %w[queued pending])
        .where('backoff_seconds <= 0 OR updated_at <= ?', Time.current)
        .update_all(status: 'running', started_at: Time.current, last_heartbeat_at: Time.current, updated_at: Time.current)
      return false unless claimed == 1

      job.reload
      true
    end

    def heartbeat!(job)
      return unless job&.persisted?
      return if job.last_heartbeat_at && job.last_heartbeat_at > 30.seconds.ago

      job.update_columns(last_heartbeat_at: Time.current, updated_at: Time.current)
      job.reload
    end

    def handle_failure(job, error)
      write_error_memory(job, error)
      if job.retryable?
        schedule_retry!(job, error)
      else
        mark_failed!(job, error.message)
        safely_post_status(job, status_body("Automyra request failed: #{error.message}")) unless chat_job?(job)
      end
    end

    def schedule_retry!(job, error)
      job.increment_retry!
      if job.retry_count.to_i >= job.max_retries.to_i
        mark_failed!(job, error.message)
        return
      end

      job.update!(
        status: 'pending',
        error_message: sanitized_failure_summary("Retry #{job.retry_count.to_i}/#{job.max_retries.to_i} scheduled in #{job.backoff_seconds.to_i} seconds: #{error.message}"),
        started_at: nil,
        finished_at: nil,
        last_heartbeat_at: nil,
        updated_at: job.backoff_seconds.seconds.from_now
      )
      mark_run_retrying(job)
    end

    def mark_failed!(job, message)
      job.update!(status: 'failed', error_message: sanitized_failure_summary(message), finished_at: Time.current, backoff_seconds: 0, last_heartbeat_at: Time.current)
      mark_run_failed(job, message)
      update_chat_failure_message(job) if chat_job?(job)
    end

    def mark_run_running(job)
      run = run_for(job)
      run&.mark_running!
      record_run_event(run, 'run.started', status: run&.status, message: 'Automyra run started.')
    end

    def mark_run_retrying(job)
      run = run_for(job)
      run&.mark_retrying!
      record_run_event(run, 'run.retrying', status: run&.status, message: 'Automyra run retry scheduled.', visible_to_user: false)
    end

    def mark_run_failed(job, message)
      run = run_for(job)
      failure_summary = sanitized_failure_summary(message)
      run&.mark_failed!(response_snapshot: { error: failure_summary }.to_json)
      record_run_event(run, 'run.failed', status: run&.status, message: failure_summary)
    end

    def mark_run_completed(job, parsed, proposals)
      run = run_for(job)
      run&.mark_completed!(
        response_snapshot: parsed.to_json,
        tool_calls: Array(parsed['tool_calls']).to_json,
        proposals: Array(proposals).map { |proposal| proposal_snapshot(proposal) }.to_json,
        llm_calls: llm_calls_snapshot(parsed).to_json,
        total_tokens: total_tokens_snapshot(parsed).to_json
      )
      record_run_event(run, 'run.completed', status: run&.status, message: 'Automyra run completed.', payload: { sources_used: completed_sources_used(job, parsed) })
    end

    def record_run_event(run, event_type, status: nil, message: nil, visible_to_user: true, payload: nil)
      return unless defined?(AutomyraBridge::RunEventRecorder)

      AutomyraBridge::RunEventRecorder.record(
        run: run,
        event_type: event_type,
        status: status,
        message: message,
        payload: payload,
        visible_to_user: visible_to_user
      )
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridgeRunEvent recording failed for #{event_type}: #{e.message}") if defined?(Rails)
      nil
    end

    def run_for(job)
      return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists? && job

      AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id)
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridgeRun lookup failed for job #{job&.id}: #{e.message}") if defined?(Rails)
      nil
    end

    def proposal_snapshot(proposal)
      {
        id: proposal.id,
        action_type: proposal.action_type,
        status: proposal.status,
        payload: proposal.payload
      }
    end

    def llm_calls_snapshot(parsed)
      parsed['llm_calls'] || parsed['model_calls'] || parsed['usage'] || {}
    end

    def total_tokens_snapshot(parsed)
      return parsed['total_tokens'] if parsed.key?('total_tokens')
      return parsed.dig('usage', 'total_tokens') if parsed['usage'].is_a?(Hash)

      {}
    end

    def completed_sources_used(job, parsed)
      return Array(parsed['sources']).map(&:to_s).reject(&:blank?).uniq if parsed['sources'].is_a?(Array)

      snapshot = job.payload['context_snapshot'] || job.payload.dig('context', 'context_snapshot') || {}
      sources = Array(parsed['tool_calls']).map { |call| call['tool'] || call['name'] }.compact.uniq
      sources << 'context.current_page' if (snapshot['page'] || snapshot[:page]).present?
      sources
    end

    def sanitized_failure_summary(raw_message)
      message = raw_message.to_s
      return nil if message.blank?

      sanitized = message.lines.reject { |line| line.match?(/\.rb:\d+:in\s/) || line.match?(/^\s*from\s+.+:\d+/) || line.match?(/^\s*\/[^\s]+:\d+/) }.join(' ')
      sanitized.gsub!(/https?:\/\/\S+/i, '[url]')
      sanitized.gsub!(/\b(?:[a-z0-9-]+\.)+(?:local|internal|localhost|lan|test|invalid)\b/i, '[host]')
      sanitized.gsub!(/\b(?:localhost|127\.0\.0\.1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b/i, '[host]')
      sanitized.gsub!(/\b(?:token|api[_-]?key|secret|password|authorization|bearer)\b\s*[:=]\s*\S+/i, '\\1=[redacted]')
      sanitized.gsub!(/\bBearer\s+\S+/i, 'Bearer [redacted]')
      sanitized.gsub!(/\b[A-Za-z0-9_\-.]{32,}\b/, '[redacted]')
      sanitized.squish.truncate(250)
    end

    def update_chat_failure_message(job)
      placeholder = AutomyraBridgeChatMessage.where(job_id: job.id, role: 'assistant').order(:id).last
      return unless placeholder

      placeholder.update!(status: 'failed', content: 'Unable to get response. Retry?')
      placeholder.chat_thread.increment_unread!(placeholder.user_id, sender_type: placeholder.role)
    end

    def stale?(job)
      heartbeat_at = job.last_heartbeat_at || job.started_at
      heartbeat_at && heartbeat_at < 5.minutes.ago
    end

    def safely_post_status(job, body)
      return if chat_job?(job)

      post_status(job, body)
    rescue StandardError => e
      job.update_columns(error_message: [job.error_message, "Status post failed: #{e.message}"].compact.join('\n'), updated_at: Time.current)
    end

    def post_payload(job)
      raise 'Automyra endpoint is not configured.' if endpoint.blank?
      uri = safe_endpoint_uri!
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{token}" if token.present?
      request['X-Correlation-ID'] = job.correlation_id
      request['Idempotency-Key'] = job.idempotency_key
      request.body = (@outbound_payload || payload(job)).to_json

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', read_timeout: timeout, open_timeout: timeout) do |http|
          AutomyraBridge::UrlValidator.validate_connected_peer!(http, uri.host, @settings)
        response = http.request(request)
        raise adapter_response_error(response) unless response.is_a?(Net::HTTPSuccess)

        response
      end
    end

    def adapter_response_error(response)
      parsed = parse_adapter_error_body(response.body)
      code = parsed['error_code'].presence || parsed['error'].presence || "http_#{response.code}"
      summary = parsed['error_summary'].presence || parsed['message'].presence || "Automyra adapter returned HTTP #{response.code}."
      AdapterResponseError.new(code, sanitized_failure_summary(summary))
    end

    def parse_adapter_error_body(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def execute_autonomous_proposals(job, proposals)
      Array(proposals).select { |proposal| proposal.status == 'pending' }.each do |proposal|
        tool = AutomyraBridge::ToolRegistry.find_by_legacy_action(proposal.action_type)
        decision = AutomyraBridge::AutonomyPolicy.decide(job: job, proposal: proposal, tool: tool)
        if decision.execute?
          execute_proposal_tool(proposal, tool, job, decision.skip_authorization)
        else
          proposal.update!(status: 'failed', error_message: decision.reason) if %w[reject readonly].include?(decision.outcome)
        end
        write_action_memory(job, proposal.reload)
      end
    end

    def execute_proposal_tool(proposal, tool, job, skip_authorization = false)
      actor = status_author(job)
      if !skip_authorization && !tool.authorized?(job, actor)
        proposal.update!(status: 'failed', error_message: 'User is not authorized for this tool.')
        return
      end

      result = tool.call(proposal_job_for_tool(job, proposal), actor, proposal.payload)
      tool.verify!(result, proposal.payload)
      proposal.update!(status: 'executed', result_payload: result.to_json, executed_at: Time.current)
    rescue StandardError => e
      proposal.update!(status: 'failed', error_message: "Tool execution failed: #{e.message}")
    end

    def proposal_job_for_tool(job, proposal)
      proposal.automyra_bridge_job || job
    end

    def write_assistant_memory(job, message, parsed, proposals)
      container = memory_container(job)
      return unless container

      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: status_author(job),
        role: 'assistant',
        event_type: 'assistant_reply',
        content: message,
        payload: { response: parsed, proposals: Array(proposals).map(&:id) },
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
    end

    def write_model_response_memory(job, parsed)
      container = memory_container(job)
      return unless container

      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: status_author(job),
        role: 'assistant',
        event_type: 'model_response',
        content: response_text(parsed),
        payload: parsed,
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
    end

    def write_action_memory(job, proposal)
      container = memory_container(job)
      return unless container

      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: job.user,
        role: 'assistant',
        event_type: 'tool_call',
        content: "Automyra requested #{proposal.action_type}.",
        payload: { proposal_id: proposal.id, action_type: proposal.action_type, tool: proposal.payload['tool'], input: proposal.payload },
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: job.user,
        role: 'audit',
        event_type: 'tool_result',
        content: "Automyra #{proposal.status}: #{proposal.action_type}.",
        payload: { proposal_id: proposal.id, action_type: proposal.action_type, status: proposal.status, error: proposal.error_message },
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
    end

    def write_outbound_memory(job, outbound_payload)
      container = memory_container(job)
      return unless container

      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: job.user,
        role: 'system',
        event_type: 'context_snapshot',
        content: 'Redmica context sent to Automyra.',
        payload: outbound_payload.except(:tools),
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: job.user,
        role: 'system',
        event_type: 'tool_schema_list',
        content: 'Redmica tool schemas sent to Automyra.',
        payload: { tools: outbound_payload[:tools] },
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
    end

    def write_error_memory(job, error)
      container = memory_container(job)
      return unless container

      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: status_author(job),
        role: 'error',
        event_type: 'error',
        content: error.message,
        payload: { error: error.class.name },
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
    end

    def memory_references(job)
      return { job_id: job.id } unless chat_job?(job)

      thread = memory_container(job)
      run = run_for(job)
      {
        chat_thread_id: thread&.id,
        chat_message_id: job.source_id,
        run_id: run&.id,
        snapshot_reference: thread&.page_key.presence || thread&.title_display,
        job_id: job.id
      }
    end

    def memory_container(job)
      case job.source_type
      when 'AutomyraBridgeChatMessage'
        AutomyraBridgeChatMessage.find_by(id: job.source_id)&.chat_thread
      when 'TaskHub::TaskComment'
        TaskHub::TaskComment.find_by(id: job.source_id)&.task
      when 'Journal'
        Journal.find_by(id: job.source_id)&.journalized
      when 'WebhookIncoming'
        job.project
      end
    end

    def payload(job)
      if chat_job?(job)
        chat_message = AutomyraBridgeChatMessage.find_by(id: job.source_id)
        thread = chat_message&.chat_thread
        return {
          action: 'chat_request',
          instruction: chat_request_instruction,
          user: { id: job.user_id, name: job.user.name },
          project: { id: job.project_id, name: job.project.name, identifier: job.project.identifier },
          tools: AutomyraBridge::ToolRegistry.schemas_for_job(job),
          request: job.payload,
          context: {
            thread_history: thread_history(thread),
            memory_recaps: recent_run_summaries(job),
            context_snapshot: job.payload['context_snapshot'] || job.payload.dig('context', 'context_snapshot')
          }
        }
      end

      {
        action: 'mention_response',
        instruction: job.source_type == 'WebhookIncoming' ? email_ingestion_instruction : mention_request_instruction,
        user: { id: job.user_id, name: job.user.name },
        project: { id: job.project_id, name: job.project.name, identifier: job.project.identifier },
        tools: AutomyraBridge::ToolRegistry.schemas_for_job(job),
        request: job.payload
      }
    end

    def tool_prompt_contract
      [
        'Prefer tool_calls using the provided Redmica tools.',
        'When the user asks about Redmica data such as tasks, issues, or projects, call the available read tools instead of guessing or stopping at a promise.',
        'Product vocabulary: tasks means Task Hub tasks; issues means Redmica issues. Do not confuse Task Hub tasks with Redmica issues.',
        'Do not provide final-answer text such as "I will search", "Let me check", or "I will look that up" unless a tool call was actually made or concrete data is included.'
      ].join(' ')
    end

    def chat_request_instruction
      "Respond to the Redmica chat message. #{tool_prompt_contract}"
    end

    def mention_request_instruction
      "Respond to the Redmica @automyra mention. #{tool_prompt_contract} Do not modify Redmica directly outside these tools."
    end

    def email_ingestion_instruction
      "Process the inbound Outlook email and propose or perform the requested Redmica action using the provided tools. #{tool_prompt_contract} Respect the destination field when it is issue, task, wiki, or ask. Do not modify Redmica directly outside these tools."
    end

    def thread_history(thread)
      return [] unless thread

      thread.chat_messages.order(:id).last(20).map do |msg|
        {
          id: msg.id,
          role: msg.role,
          content: msg.content.to_s.truncate(1000),
          status: msg.status,
          created_at: msg.created_at
        }
      end
    end

    def recent_run_summaries(job)
      container = memory_container(job)
      return [] unless container && defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?

      AutomyraBridgeMemoryEvent.where(container_type: container.class.name, container_id: container.id, event_type: 'assistant_run_summary').order(created_at: :desc).limit(5).map do |event|
        parsed = JSON.parse(event.payload.to_s.presence || '{}') rescue {}
        {
          summary: parsed['summary'].presence || event.content.to_s,
          run_id: parsed['run_id'],
          source_type: parsed['source_type'],
          source_id: parsed['source_id']
        }.compact
      end.reverse
    end

    def update_chat_assistant_message(job, message, proposals)
      chat_message = AutomyraBridgeChatMessage.find_by(id: job.source_id)
      thread = chat_message&.chat_thread
      return unless thread

      proposal_id = Array(proposals).first&.id
      placeholder = thread.chat_messages.where(job_id: job.id, role: 'assistant', status: 'pending').order(:id).last

      if placeholder
        AutomyraBridge::ChatMessageCreator.update_assistant_message!(placeholder, message, proposal_id)
      else
        AutomyraBridge::ChatMessageCreator.create_assistant_reply!(thread, message, proposal_id)
      end
    end

    def chat_job?(job)
      job&.source_type == 'AutomyraBridgeChatMessage'
    end

    def parse_response(body)
      normalize_tool_call_response(JSON.parse(body.to_s))
    rescue JSON::ParserError
      raise 'Automyra returned invalid JSON.'
    end

    def response_text(parsed)
      source = parsed['response'].presence || parsed['message'].presence || parsed['body'].presence || parsed['text'].presence
      source = nil if tool_call_json_text?(source)
      if source.blank? && parsed['tool_calls'].is_a?(Array) && parsed['tool_calls'].any?
        source = 'Automyra reviewed the page context and requested additional Redmica context.'
      end
      source.to_s.presence || 'Automyra completed the request without a message.'
    end

    def normalize_tool_call_response(parsed)
      return parsed unless parsed.is_a?(Hash)

      %w[response message body text].each do |key|
        tool_calls = extract_tool_calls_from_text(parsed[key])
        next if tool_calls.blank?

        parsed['tool_calls'] = Array(parsed['tool_calls']) + tool_calls
        parsed[key] = nil
      end
      parsed
    end

    def extract_tool_calls_from_text(text)
      stripped = strip_markdown_fence(text.to_s.strip)
      return [] unless stripped.start_with?('{', '[')

      decoded = JSON.parse(stripped)
      raw_calls = decoded.is_a?(Hash) ? decoded['tool_calls'] || decoded[:tool_calls] || [decoded] : decoded
      Array(raw_calls).filter_map do |call|
        next unless call.is_a?(Hash)

        name = call['tool'] || call['name'] || call.dig('function', 'name')
        arguments = call['input'] || call['arguments'] || call.dig('function', 'arguments') || {}
        arguments = JSON.parse(arguments) if arguments.is_a?(String) && arguments.strip.start_with?('{')
        next if name.blank?

        { 'name' => name, 'input' => arguments.is_a?(Hash) ? arguments : {} }
      end
    rescue JSON::ParserError
      []
    end

    def tool_call_json_text?(text)
      extract_tool_calls_from_text(text).any?
    end

    def strip_markdown_fence(text)
      text.sub(/\A```(?:json)?\s*/i, '').sub(/```\s*\z/, '').strip
    end

    def post_status(job, body)
      case job.source_type
      when 'TaskHub::TaskComment'
        source = TaskHub::TaskComment.find_by(id: job.source_id)
        return unless source

        source.task.comments.create!(author: status_author(job), body: body)
      when 'Journal'
        source = Journal.find_by(id: job.source_id)
        return unless source&.journalized.is_a?(Issue)

        issue = source.journalized
        issue.init_journal(status_author(job), body)
        issue.save!
      end
    end

    def cancelled?(job)
      job.reload.status == 'cancelled'
    end

    def status_author(job)
      User.where(login: 'Automyra', type: 'User', status: Principal::STATUS_ACTIVE).order(:id).last || job.user
    end

    def endpoint
      @settings['automyra_endpoint'].to_s.strip
    end

    def valid_endpoint?
      AutomyraBridge::UrlValidator.safe?(endpoint, @settings)
    end

    def safe_endpoint_uri!
      AutomyraBridge::UrlValidator.validate!(endpoint, @settings)
    rescue ArgumentError => e
      raise e.message
    end


    def token
      @settings['automyra_token'].to_s.strip
    end

    def timeout
      @settings['request_timeout_seconds'].to_i.clamp(1, 120)
    end
  end
end
