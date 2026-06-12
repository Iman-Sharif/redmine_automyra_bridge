class AutomyraBridgeWebhookDelivery < ApplicationRecord
  self.table_name = 'automyra_bridge_webhook_deliveries'

  validates :idempotency_key, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :delivered_at, presence: true

  def self.already_delivered?(idempotency_key)
    exists?(idempotency_key: idempotency_key)
  end

  def self.record_delivery!(idempotency_key:, event_type:)
    create!(
      idempotency_key: idempotency_key,
      event_type: event_type,
      status: 'delivered',
      delivered_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
