module AutomyraBridge
  class AssistantRunProcessor
    DEFAULT_MAX_STEPS = 4
    FINAL_ANSWER_RETRY_INSTRUCTION = 'You must complete your answer using the available Redmica tools. Do not stop at a promise; execute the necessary tool call and return concrete data.'.freeze
    FINAL_ANSWER_FAILURE_MESSAGE = 'Automyra could not complete the request because no tool was called to retrieve the required Redmica data.'.freeze

    def initialize(job_processor:, settings: Setting.plugin_redmine_automyra_bridge)
      @job_processor = job_processor
      @settings = settings || {}
    end

    def process(job, outbound_payload = nil)
      @job = job
      @run = run_for(job)
      @messages = initial_messages(job, outbound_payload)
      @last_parsed = nil
      @proposals = []
      @memory_events_referenced = []
      @retried_final_answer = false

      max_steps.times do |step_index|
        ensure_not_cancelled!
        parsed = call_provider(job, outbound_payload)
        @last_parsed = parsed
        tool_calls = Array(parsed['tool_calls']).select { |item| item.is_a?(Hash) }
        assistant_text = response_text(parsed)

        if tool_calls.empty?
          if incomplete_final_answer?(assistant_text)
            if @retried_final_answer
              graceful_failure(job, FINAL_ANSWER_FAILURE_MESSAGE)
              return job
            end

            @retried_final_answer = true
            append_final_answer_retry_instruction
            next
          end

          @proposals.concat(AutomyraBridge::ActionProposalCreator.create_from_response(job, parsed)) if legacy_proposals?(parsed)
          record_final_assistant_message(job, parsed, assistant_text)
          complete_job(job, parsed, assistant_text)
          return job
        end

        append_assistant_message(parsed, assistant_text)
        process_tool_calls(job, tool_calls, step_index)
      end

      record_event('run.max_steps_reached', status: @run&.status, message: 'Automyra reached the maximum tool loop steps without a final answer.')
      graceful_failure(job, 'Automyra reached the maximum tool loop steps without a final answer.')
      job
    end

    private

    def max_steps
      configured = @settings['assistant_max_steps'].presence || @settings['max_steps'].presence
      configured.to_i.positive? ? configured.to_i : DEFAULT_MAX_STEPS
    end

    def initial_messages(job, outbound_payload)
      payload = outbound_payload || @job_processor.send(:payload, job)
      history = Array(payload.dig(:context, :thread_history) || payload.dig('context', 'thread_history'))
      recaps = Array(payload.dig(:context, :memory_recaps) || payload.dig('context', 'memory_recaps'))
      messages = history.map { |message| { 'role' => message[:role] || message['role'], 'content' => message[:content] || message['content'] }.compact }
      return messages if recaps.blank?

      [{ 'role' => 'system', 'content' => memory_recap_text(recaps) }] + messages
    end

    def call_provider(job, outbound_payload)
      append_recalled_memory_context(job)
      payload = provider_payload(job, outbound_payload)
      @job_processor.instance_variable_set(:@outbound_payload, payload)
      response = @job_processor.send(:post_payload, job)
      @job_processor.send(:heartbeat!, job)
      @job_processor.send(:parse_response, response.body)
    end

    def provider_payload(job, outbound_payload)
      base = (outbound_payload || @job_processor.send(:payload, job)).deep_dup
      base[:messages] = @messages
      base[:tools] = AutomyraBridge::ToolRegistry.schemas_for_job(job)
      base[:instruction] = [@job_processor.send(:chat_request_instruction), job.payload['instruction_hint']].compact.join("\n")
      base[:context] ||= {}
      base[:context][:context_snapshot] ||= job.payload['context_snapshot'] || job.payload.dig('context', 'context_snapshot')
      base
    end

    def process_tool_calls(job, tool_calls, step_index)
      tool_calls.each_with_index do |tool_call, index|
        ensure_not_cancelled!
        tool = AutomyraBridge::ToolRegistry.find(tool_call['tool'] || tool_call['name'])
        record_event('tool_call.requested', role: 'assistant', message: tool_call_name(tool_call), payload: tool_call)

        result = if tool.nil?
                   { error: 'Unknown tool.', tool: tool_call_name(tool_call) }
                 elsif tool.risk_level == 'read'
                   execute_read_tool(job, tool, tool_call)
                 else
                   create_write_proposal(job, tool_call)
                 end

        record_event('tool_call.completed', role: 'tool', message: tool_call_name(tool_call), payload: result)
        append_tool_result(tool_call, result, step_index, index)
        if result.is_a?(Hash) && result[:error].present?
          graceful_failure(job, "Tool error from #{tool_call_name(tool_call)}: #{result[:error]}")
          return
        end
      end
    end

    def execute_read_tool(job, tool, tool_call)
      return { tool: tool.name, error: 'User is not authorized for this tool.' } unless tool.authorized?(job, job.user)

      input = tool_call['input'].is_a?(Hash) ? tool_call['input'] : tool_call['arguments'].is_a?(Hash) ? tool_call['arguments'] : {}
      { tool: tool.name, result: tool.call(job, job.user, input) }
    rescue StandardError => e
      { tool: tool.name, error: e.message }
    end

    def create_write_proposal(job, tool_call)
      proposals = AutomyraBridge::ActionProposalCreator.create_from_response(job, { 'tool_calls' => [tool_call] })
      @proposals.concat(proposals)
      proposal = proposals.first
      record_event('action_proposal.created', role: 'assistant', message: tool_call_name(tool_call), payload: proposal_payload(proposal, tool_call))
      { tool: tool_call_name(tool_call), proposal_id: proposal&.id, status: proposal&.status || 'not_created' }
    end

    def append_assistant_message(parsed, assistant_text)
      message = { 'role' => 'assistant', 'content' => assistant_text }
      message['tool_calls'] = parsed['tool_calls'] if parsed['tool_calls'].present?
      @messages << message
    end

    def append_tool_result(tool_call, result, step_index, index)
      @messages << {
        'role' => 'tool',
        'tool_call_id' => tool_call['id'].presence || "step-#{step_index}-tool-#{index}",
        'name' => tool_call_name(tool_call),
        'content' => result.to_json
      }
    end

    def incomplete_final_answer?(assistant_text)
      AutomyraBridge::FinalAnswerGuard.call(
        response_text: assistant_text,
        tool_calls_present: false,
        has_tool_results: @messages.any? { |message| message['role'] == 'tool' }
      )[:incomplete]
    end

    def append_final_answer_retry_instruction
      @messages << { 'role' => 'system', 'content' => FINAL_ANSWER_RETRY_INSTRUCTION }
    end

    def record_final_assistant_message(job, parsed, assistant_text)
      @job_processor.send(:write_model_response_memory, job, parsed)
      @job_processor.send(:write_assistant_memory, job, assistant_text, parsed, @proposals)
      @job_processor.send(:update_chat_assistant_message, job, assistant_text, @proposals)
    end

    def complete_job(job, parsed, _assistant_text)
      parsed['sources'] = source_names(parsed, run_event_summaries)
      @job_processor.send(:mark_run_completed, job, parsed, @proposals)
      write_run_summary_memory(job, parsed)
      job.update!(status: 'succeeded', response_payload: parsed.to_json, error_message: nil, backoff_seconds: 0, finished_at: Time.current, last_heartbeat_at: Time.current)
    end

    def write_run_summary_memory(job, parsed)
      thread = chat_thread_for(job)
      return unless thread

      events = run_event_summaries
      AutomyraBridge::ChatMemoryWriter.write_run_summary(
        job: job,
        thread: thread,
        run: @run,
        final_answer: response_text(parsed),
        tool_calls: tools_used(parsed, events),
        timeline: simplified_timeline(events),
        page_context: page_context_for(job),
        user_query: job.payload['body'] || job.payload.dig('request', 'body')
      )
    rescue StandardError => e
      Rails.logger.warn("Automyra assistant run summary memory write failed: #{e.message}") if defined?(Rails)
    end

    def run_summary_payload(job, parsed)
      events = run_event_summaries
      {
        event_type: 'assistant_run_summary',
        run_id: @run&.id,
        source_type: job.source_type,
        source_id: job.source_id,
        summary: compact_run_summary(parsed, events),
        tools_used: tools_used(parsed, events),
        proposals_created: Array(@proposals).map { |proposal| { id: proposal.id, action_type: proposal.action_type, status: proposal.status } },
        run_events: events,
        sources_used: sources_used(parsed, events)
      }.compact
    end

    def compact_run_summary(parsed, events)
      text = response_text(parsed).to_s.squish
      event_text = events.map { |event| event[:message] }.compact.join(' ')
      [text.presence, event_text.presence].compact.join(' ').truncate(1000)
    end

    def run_event_summaries
      return [] unless @run && AutomyraBridge::RunEventRecorder.available?

      @run.run_events.order(:id).last(20).map do |event|
        { id: event.id, event_type: event.event_type, message: event.message, status: event.status }.compact
      end
    end

    def tools_used(parsed, events)
      names = Array(parsed['tool_calls']).map { |call| tool_call_name(call) }
      names += events.select { |event| event[:event_type].to_s.start_with?('tool_call.') }.map { |event| event[:message].to_s }
      names.reject(&:blank?).uniq
    end

    def sources_used(parsed, events)
      snapshot = @job.payload['context_snapshot'] || @job.payload.dig('context', 'context_snapshot') || {}
      [
        *tools_used(parsed, events).map { |name| { type: 'tool', name: name } },
        ({ type: 'page_context', context: snapshot.dig('page') || snapshot[:page] } if (snapshot.dig('page') || snapshot[:page]).present?),
        *Array(@memory_events_referenced).map { |event| { type: 'memory_event', id: event.id, event_type: event.event_type } }
      ].compact
    end

    def source_names(parsed, events)
      names = tools_used(parsed, events)
      snapshot = @job.payload['context_snapshot'] || @job.payload.dig('context', 'context_snapshot') || {}
      page = snapshot['page'] || snapshot[:page]
      names << 'context.current_page' if page.present?
      names.reject(&:blank?).uniq
    end

    def simplified_timeline(events)
      events.map do |event|
        type = event[:event_type].to_s
        next { type: 'started', message: event[:message] } if type == 'run.started'
        next { type: 'tool_call', name: event[:message], status: event[:status] } if type.start_with?('tool_call.')
        next { type: 'proposal', message: event[:message], status: event[:status] } if type.include?('proposal')
        next { type: 'completed', message: event[:message] } if type == 'run.completed'
      end.compact
    end

    def append_recalled_memory_context(job)
      events = recall_memory_events(job)
      @memory_events_referenced = events
      @messages.reject! { |message| message['role'] == 'system' && message['name'] == 'automyra_memory_context' }
      return if events.blank?

      @messages << { 'role' => 'system', 'name' => 'automyra_memory_context', 'content' => condensed_memory_context(events) }
    end

    def recall_memory_events(job)
      thread = chat_thread_for(job)
      return [] unless thread && defined?(AutomyraBridge::MemoryReader) && AutomyraBridge::MemoryReader.configured?

      AutomyraBridge::MemoryReader.recall(thread_key: thread.channel_key.presence || thread.page_key.presence || "redmica-chat-#{thread.id}", limit: 3)
    rescue StandardError
      []
    end

    def condensed_memory_context(events)
      lines = events.map { |event| "- #{event[:event_type] || event['event_type']}: #{(event[:content] || event['content']).to_s.squish.truncate(220)}" }
      "Compact recalled memory for this thread/channel (use only for continuity, do not expose hidden details):\n#{lines.join("\n")}".truncate(1200)
    end

    def chat_thread_for(job)
      return unless job.source_type == 'AutomyraBridgeChatMessage'

      AutomyraBridgeChatMessage.find_by(id: job.source_id)&.chat_thread
    end

    def page_context_for(job)
      context = job.payload['context'] || job.payload[:context] || {}
      snapshot = job.payload['context_snapshot'] || job.payload.dig('context', 'context_snapshot') || {}
      page = snapshot['page'] || snapshot[:page] || {}
      context.merge(page_type: context['page_type'] || context[:page_type] || page['type'] || page[:type], page_id: context['page_id'] || context[:page_id] || page['id'] || page[:id])
    end

    def memory_recap_text(recaps)
      lines = recaps.map { |recap| "- #{(recap[:summary] || recap['summary']).to_s.squish}" }.reject { |line| line == '- ' }
      "Recent Automyra memory recap for this thread/source:\n#{lines.join("\n")}".truncate(1500)
    end

    def graceful_failure(job, message)
      @run&.mark_failed!(response_snapshot: { error: message, last_response: @last_parsed }.to_json)
      record_event('run.failed', status: @run&.status, message: message)
      write_run_summary_memory(job, { 'response' => message, 'sources' => source_names(@last_parsed || {}, run_event_summaries) })
      @job_processor.send(:update_chat_assistant_message, job, message, @proposals) if job.source_type == 'AutomyraBridgeChatMessage'
      job.update!(status: 'failed', error_message: message, backoff_seconds: 0, finished_at: Time.current, last_heartbeat_at: Time.current)
    end

    def ensure_not_cancelled!
      @job.reload
      raise 'Automyra job was cancelled.' if @job.status == 'cancelled' || @job.respond_to?(:cancelled?) && @job.cancelled? || @run&.respond_to?(:cancelled?) && @run.cancelled?
    end

    def response_text(parsed)
      @job_processor.send(:response_text, parsed)
    end

    def tool_call_name(tool_call)
      (tool_call['tool'] || tool_call['name']).to_s
    end

    def proposal_payload(proposal, tool_call)
      return { tool_call: tool_call, created: false } unless proposal

      { id: proposal.id, action_type: proposal.action_type, status: proposal.status, tool_call: tool_call }
    end

    def legacy_proposals?(parsed)
      Array(parsed['proposals']).any? || Array(parsed['actions']).any?
    end

    def record_event(event_type, status: nil, role: nil, message: nil, payload: nil, visible_to_user: true)
      AutomyraBridge::RunEventRecorder.record(run: @run, event_type: event_type, status: status, role: role, message: message, payload: payload, visible_to_user: visible_to_user, created_by: @job&.user)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("Automyra run event unavailable: #{e.message}") if defined?(Rails)
    end

    def run_for(job)
      return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists?

      AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id)
    end
  end
end
