module AutomyraBridge
  class ChatThreadSummarizer
    USER_MESSAGE_THRESHOLD = 50
    KEEP_RAW_MESSAGES = 20
    SUMMARY_LIMIT = 4000

    def self.call(thread)
      new(thread).call
    end

    def initialize(thread)
      @thread = thread
    end

    def call
      return unless @thread
      return unless AutomyraBridgeChatMessage.column_names.include?('kind')
      return if @thread.chat_messages.where(role: 'user').count <= USER_MESSAGE_THRESHOLD

      older = @thread.chat_messages.where.not(id: @thread.chat_messages.order(id: :desc).limit(KEEP_RAW_MESSAGES).select(:id)).order(:id)
      return if older.none?

      summary = build_summary(older)
      return if summary.blank?

      AutomyraBridgeChatMessage.create!(
        chat_thread: @thread,
        user: @thread.user,
        role: 'system',
        kind: 'summary',
        status: 'delivered',
        content: summary
      )
    end

    private

    def build_summary(messages)
      lines = messages.limit(200).map do |message|
        "#{message.role}: #{message.content.to_s.squish.truncate(300)}"
      end
      "Earlier chat summary:\n#{lines.join("\n").truncate(SUMMARY_LIMIT)}"
    end
  end
end
