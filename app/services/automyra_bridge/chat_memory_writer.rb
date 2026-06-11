module AutomyraBridge
  class ChatMemoryWriter
    def self.write_message(message, thread)
      return unless AutomyraBridgeMemoryEvent.table_exists?

      event_type = case message.role
                   when 'user'
                     'chat_message'
                   when 'assistant'
                     'chat_reply'
                   when 'system'
                     'chat_system'
                   else
                     return
                   end

      correlation_id = message.job&.correlation_id
      run = run_for(message)

      MemoryWriter.write(
        container: thread,
        user: message.user,
        role: message.role,
        event_type: event_type,
        content: message.content,
        payload: {},
        correlation_id: correlation_id,
        chat_thread_id: thread.id,
        chat_message_id: message.id,
        run_id: run&.id,
        snapshot_reference: snapshot_reference(thread),
        job_id: message.job_id
      )
    end

    def self.write_run_summary(job:, thread:, run:, final_answer:, tool_calls:, timeline:, page_context: {}, user_query: nil)
      return unless AutomyraBridgeMemoryEvent.table_exists?
      return unless thread

      tools = Array(tool_calls).map(&:to_s).reject(&:blank?).uniq
      answer_snippet = final_answer.to_s.squish.truncate(200)
      compact_text = [
        "Run ID: #{run&.id || 'unknown'}",
        "Query: #{sanitize_summary_text(user_query || job.payload['body'] || job.payload.dig('request', 'body'))}",
        "Answer: #{sanitize_summary_text(answer_snippet)}",
        "Tools used: #{tools.any? ? tools.join(', ') : 'none'}",
        "Page context: #{compact_page_context(page_context)}"
      ].join("\n").truncate(1200)

      payload = {
        event_type: 'assistant_run_summary',
        run_id: run&.id,
        thread_id: thread.id,
        user_id: job.user_id,
        page_type: page_context[:page_type] || page_context['page_type'],
        page_id: page_context[:page_id] || page_context['page_id'],
        user_query: sanitize_summary_text(user_query || job.payload['body'] || job.payload.dig('request', 'body')),
        final_answer: answer_snippet,
        tool_calls: tools,
        timeline: Array(timeline)
      }.compact

      MemoryWriter.write(
        container: thread,
        user: job.user,
        role: 'system',
        event_type: 'assistant_run_summary',
        content: compact_text,
        payload: payload,
        correlation_id: job.correlation_id,
        chat_thread_id: thread.id,
        run_id: run&.id,
        snapshot_reference: snapshot_reference(thread),
        job_id: job.id
      )
    end

    def self.run_for(message)
      return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists?

      AutomyraBridgeRun.find_by(source_id: message.id, source_type: 'AutomyraBridgeChatMessage')
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridgeRun lookup failed for chat message #{message&.id}: #{e.message}") if defined?(Rails)
      nil
    end

    def self.snapshot_reference(thread)
      thread.page_key.presence || thread.title_display
    end

    def self.compact_page_context(page_context)
      type = page_context[:page_type] || page_context['page_type']
      id = page_context[:page_id] || page_context['page_id']
      [type, id].reject(&:blank?).join(':').presence || 'none'
    end

    def self.sanitize_summary_text(value)
      value.to_s.squish
        .gsub(/https?:\/\/\S+/i, '[url]')
        .gsub(/\b(?:token|api[_-]?key|secret|password|authorization|bearer)\b\s*[:=]\s*\S+/i, '\\1=[redacted]')
        .gsub(/\bBearer\s+\S+/i, 'Bearer [redacted]')
        .gsub(/\b[A-Za-z0-9_\-.]{32,}\b/, '[redacted]')
        .truncate(300)
    end
  end
end
