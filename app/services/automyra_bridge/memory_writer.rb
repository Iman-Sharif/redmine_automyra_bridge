module AutomyraBridge
  class MemoryWriter
    MAX_PAYLOAD_BYTES = 10.kilobytes

    def self.write(container:, user:, role:, event_type:, content:, payload: {}, correlation_id: nil, journal_id: nil, chat_message_id: nil, chat_thread_id: nil, run_id: nil, snapshot_reference: nil, job_id: nil)
      return unless AutomyraBridgeMemoryEvent.table_exists?

      safe_payload = bounded_payload(payload, chat_thread_id: chat_thread_id, chat_message_id: chat_message_id, run_id: run_id, snapshot_reference: snapshot_reference)
      attributes = {
        container_type: container.class.name,
        container_id: container.id,
        user: user,
        role: role,
        event_type: event_type,
        content: content,
        payload: safe_payload,
        correlation_id: correlation_id,
        journal_id: journal_id
      }
      attributes[:chat_message_id] = chat_message_id if AutomyraBridgeMemoryEvent.column_names.include?('chat_message_id')
      attributes[:job_id] = job_id if job_id && AutomyraBridgeMemoryEvent.column_names.include?('job_id')

      event = AutomyraBridgeMemoryEvent.create!(attributes)
      AutomyraBridge::MemorySync.new.sync_event(event)
      event
    end

    def self.bounded_payload(payload, references = {})
      enriched = payload.presence || {}
      enriched = { value: enriched } unless enriched.is_a?(Hash)
      refs = references.compact
      enriched = enriched.merge('references' => refs) if refs.any?

      json = enriched.to_json
      return json if json.bytesize <= MAX_PAYLOAD_BYTES

      {
        truncated: true,
        original_bytesize: json.bytesize,
        data: json.byteslice(0, MAX_PAYLOAD_BYTES - 200).to_s
      }.to_json
    end
  end
end
