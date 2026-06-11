require 'securerandom'

module AutomyraBridge
  class ChatMessageCreator
    def self.create_user_message!(user, thread, content, context: nil)
      new.create_user_message!(user, thread, content, context: context)
    end

    def self.create_assistant_placeholder!(thread, job, context: nil)
      new.create_assistant_placeholder!(thread, job, context: context)
    end

    def self.update_assistant_message!(message, content, proposal_id)
      new.update_assistant_message!(message, content, proposal_id)
    end

    def self.create_system_message!(thread, content, context: nil)
      new.create_system_message!(thread, content, context: context)
    end

    def self.create_assistant_reply!(thread, content, proposal_id, context: nil)
      new.create_assistant_reply!(thread, content, proposal_id, context: context)
    end

    def create_user_message!(user, thread, content, context: nil)
      AutomyraBridgeChatMessage.transaction do
        message = AutomyraBridgeChatMessage.create!(message_metadata(thread, context).merge(
          chat_thread: thread,
          user: user,
          role: 'user',
          content: content,
          status: 'sent'
        ))

        AuditRecorder.record(
          'chat_message_sent',
          user,
          project_id: thread.project_id,
          correlation_id: SecureRandom.uuid,
          message_id: message.id,
          thread_id: thread.id,
          role: 'user'
        )

        ChatMemoryWriter.write_message(message, thread)
        ChatThreadSummarizer.call(thread)

        message
      end
    end

    def create_assistant_placeholder!(thread, job, context: nil)
      AutomyraBridgeChatMessage.transaction do
        message = AutomyraBridgeChatMessage.create!(message_metadata(thread, context).merge(
          chat_thread: thread,
          user: thread.user,
          role: 'assistant',
          content: '',
          status: 'pending',
          job: job
        ))

        thread.increment_unread!(message.user_id, sender_type: message.role)
        ChatMemoryWriter.write_message(message, thread)

        message
      end
    end

    def update_assistant_message!(message, content, proposal_id)
      return message unless message.status == 'pending'

      AutomyraBridgeChatMessage.transaction do
        message.update!(
          content: content,
          status: 'delivered',
          proposal_id: proposal_id
        )

        message.chat_thread.increment_unread!(message.user_id, sender_type: message.role)
        ChatMemoryWriter.write_message(message, message.chat_thread)

        AuditRecorder.record(
          'chat_reply_delivered',
          message.user,
          project_id: message.chat_thread.project_id,
          correlation_id: SecureRandom.uuid,
          message_id: message.id,
          thread_id: message.chat_thread.id,
          role: 'assistant',
          proposal_id: proposal_id
        )

        message
      end
    end

    def create_system_message!(thread, content, context: nil)
      AutomyraBridgeChatMessage.transaction do
        message = AutomyraBridgeChatMessage.create!(message_metadata(thread, context).merge(
          chat_thread: thread,
          user: thread.user,
          role: 'system',
          content: content,
          status: 'delivered'
        ))

        thread.increment_unread!(message.user_id, sender_type: message.role)
        ChatMemoryWriter.write_message(message, thread)

        message
      end
    end

    def create_assistant_reply!(thread, content, proposal_id, context: nil)
      AutomyraBridgeChatMessage.transaction do
        message = AutomyraBridgeChatMessage.create!(message_metadata(thread, context).merge(
          chat_thread: thread,
          user: thread.user,
          role: 'assistant',
          content: content,
          status: 'delivered',
          proposal_id: proposal_id
        ))

        thread.increment_unread!(message.user_id, sender_type: message.role)
        ChatMemoryWriter.write_message(message, thread)

        AuditRecorder.record(
          'chat_message_sent',
          thread.user,
          project_id: thread.project_id,
          correlation_id: SecureRandom.uuid,
          message_id: message.id,
          thread_id: thread.id,
          role: 'assistant',
          proposal_id: proposal_id
        )

        message
      end
    end

    private

    def message_metadata(thread, context)
      context ||= {}
      snapshot = context[:context_snapshot].is_a?(Hash) ? context[:context_snapshot] : {}
      page = snapshot[:page] || snapshot['page'] || {}
      metadata = {
        page_type: context[:page_type].presence || thread.page_type,
        page_id: (context[:page_id].presence || thread.page_id),
        project_id: (context[:project_id].presence || thread.project_id),
        url_path: context[:url_path].presence || thread.url_path,
        page_title: context[:page_title].presence || page[:title] || page['title'],
        snapshot_reference: snapshot_reference(thread, context)
      }
      metadata.select { |column, value| AutomyraBridgeChatMessage.column_names.include?(column.to_s) && value.present? }
    end

    def snapshot_reference(thread, context)
      context[:snapshot_reference].presence || thread.channel_key.presence || thread.page_key.presence || thread.title_display
    end
  end
end
