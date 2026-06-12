class AutomyraBridgeMemoryEvent < ApplicationRecord
  self.table_name = 'automyra_bridge_memory_events'

  ROLES = %w[user assistant action audit system error].freeze
  EVENT_TYPES = %w[mention user_mention context_snapshot tool_schema_list model_response tool_call tool_result assistant_reply error action_planned action_executed action_blocked confirmation_requested chat_message chat_reply chat_system assistant_run_summary].freeze
  SYNC_STATUSES = %w[pending skipped synced failed].freeze

  belongs_to :user, optional: true

  validates :container_type, :container_id, :role, :event_type, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :sync_status, inclusion: { in: SYNC_STATUSES }, if: -> { has_attribute?(:sync_status) }

  def self.for_container(type, id)
    return none unless table_exists?

    where(container_type: type, container_id: id)
  end

  def payload_hash
    JSON.parse(payload.to_s.presence || '{}')
  rescue JSON::ParserError
    {}
  end
end
