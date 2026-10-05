# frozen_string_literal: true

class AutomyraBridgeWebhookDelivery < ApplicationRecord
  STATUSES = %w[pending resolved retrying exhausted cancelled].freeze

  belongs_to :project, optional: true

  validates :event_type, :delivery_id, :payload, :next_retry_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :delivery_id, uniqueness: true
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
  validates :max_retries, numericality: { greater_than_or_equal_to: 0 }

  scope :pending, -> { where(status: 'pending') }
  scope :ready_to_check, -> { pending.where('next_retry_at <= ?', Time.current) }
  scope :for_target, ->(type, id) { where(target_type: type, target_id: id) }
  scope :recent, -> { order(created_at: :desc) }

  def payload_hash
    JSON.parse(payload.to_s.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def retryable?
    retry_count < max_retries
  end

  def increment_retry!(interval_minutes)
    next_count = retry_count + 1
    update!(
      retry_count: next_count,
      next_retry_at: Time.current + interval_minutes.minutes,
      status: 'pending'
    )
  end

  def mark_resolved!(journal_id, method)
    update!(
      status: 'resolved',
      detected_journal_id: journal_id,
      detection_method: method
    )
  end

  def mark_exhausted!(error_message = nil)
    update!(
      status: 'exhausted',
      last_error: error_message
    )
  end

  def mark_cancelled!
    update!(status: 'cancelled')
  end

  def next_delivery_id
    "#{delivery_id}-retry-#{retry_count + 1}"
  end
end
