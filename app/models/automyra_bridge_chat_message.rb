class AutomyraBridgeChatMessage < ActiveRecord::Base
  ROLES = %w[user assistant system].freeze
  STATUSES = %w[pending sent delivered failed].freeze

  belongs_to :chat_thread,
             class_name: 'AutomyraBridgeChatThread',
             foreign_key: 'chat_thread_id'
  belongs_to :user, class_name: 'User'
  belongs_to :job,
             class_name: 'AutomyraBridgeJob',
             optional: true
  belongs_to :proposal,
             class_name: 'AutomyraBridgeActionProposal',
             optional: true

  validates :chat_thread_id, :user_id, :role, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: %w[message summary], allow_blank: true }, if: -> { column_names.include?('kind') }

  acts_as_attachable view_permission: :use_automyra_bridge,
                     delete_permission: :use_automyra_bridge if respond_to?(:acts_as_attachable)

  scope :by_thread, lambda { |thread_id| where(chat_thread_id: thread_id) }
  scope :user_messages, -> { where(role: 'user') }
  scope :assistant_messages, -> { where(role: 'assistant') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
  scope :summaries, -> { where(kind: 'summary') if column_names.include?('kind') }

  def mark_sent!
    update!(status: 'sent')
  end

  def mark_delivered!
    update!(status: 'delivered')
  end

  def mark_failed!(error)
    update!(status: 'failed', content: "Error: #{error}")
  end

  def has_proposal?
    proposal_id.present?
  end
end
