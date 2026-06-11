module AutomyraBridge
  class ChatPollService
    def self.poll(thread, since_message_id: nil, since_updated_at: nil)
      return empty_result if thread.nil? || thread.status == 'archived'

      server_time = Time.current
      messages = poll_scope(thread, since_message_id, since_updated_at)

      new_messages = messages.map { |msg| message_to_hash(msg) }

      {
        has_updates: new_messages.any?,
        new_messages: new_messages,
        unread_count: thread.unread_count.to_i,
        thread_status: thread.status,
        last_message_id: thread.chat_messages.maximum(:id).to_i,
        last_seen_update_at: latest_update_at(thread, server_time).utc.iso8601(3),
        server_time: server_time.utc.iso8601(3)
      }
    end

    def self.empty_result
      {
        has_updates: false,
        new_messages: [],
        unread_count: 0,
        thread_status: 'archived',
        last_message_id: 0,
        last_seen_update_at: Time.current.utc.iso8601(3),
        server_time: Time.current.utc.iso8601(3)
      }
    end

    def self.poll_scope(thread, since_message_id, since_updated_at)
      scope = thread.chat_messages
      conditions = []
      values = []

      if since_message_id.present?
        conditions << 'id > ?'
        values << since_message_id.to_i
      end

      parsed_since_updated_at = parse_time(since_updated_at)
      if parsed_since_updated_at.present?
        conditions << 'updated_at > ?'
        values << parsed_since_updated_at
      end

      scope = scope.where(conditions.join(' OR '), *values) if conditions.any?
      scope.order(:updated_at, :id).distinct
    end

    def self.parse_time(value)
      return value if value.respond_to?(:to_time)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def self.latest_update_at(thread, fallback)
      thread.chat_messages.maximum(:updated_at) || fallback
    end

    def self.message_to_hash(message)
      {
        id: message.id,
        role: message.role,
        content: message.content,
        status: message.status,
        created_at: message.created_at.utc.iso8601(3),
        updated_at: message.updated_at.utc.iso8601(3),
        has_proposal: message.has_proposal?,
        proposal_id: message.proposal_id,
        job_id: message.job_id
      }
    end
    private_class_method :poll_scope, :parse_time, :latest_update_at
    private_class_method :message_to_hash
  end
end
