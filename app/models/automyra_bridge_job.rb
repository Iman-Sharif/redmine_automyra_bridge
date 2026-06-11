class AutomyraBridgeJob < ActiveRecord::Base
  STATUSES = %w[queued pending running succeeded failed cancelled].freeze

  belongs_to :project
  belongs_to :user
  has_many :action_proposals,
           class_name: 'AutomyraBridgeActionProposal',
           foreign_key: 'automyra_bridge_job_id',
           dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :source_type, :source_id, :project, :user, :correlation_id, :idempotency_key, presence: true

  scope :queued, -> { where(status: %w[queued pending]) }
  scope :ready_to_process, -> { queued.where('backoff_seconds <= 0 OR updated_at <= ?', Time.current) }
  scope :stale, -> { where(status: 'running').where('last_heartbeat_at < ?', 5.minutes.ago) }
  scope :stale_running, lambda {
    where(status: 'running')
      .where('COALESCE(last_heartbeat_at, started_at) < ?', 10.minutes.ago)
  }

  def payload
    JSON.parse(request_payload.to_s.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def retryable?
    retry_count.to_i < max_retries.to_i
  end

  def increment_retry!
    next_retry_count = retry_count.to_i + 1
    update!(
      retry_count: next_retry_count,
      backoff_seconds: [30, 60, 120, 300][retry_count.to_i] || 300
    )
  end

  def next_backoff_seconds
    5 * (5**retry_count.to_i)
  end
end
