class AutomyraBridgeRun < ApplicationRecord
  STATUSES = %w[queued running retrying failed completed cancelled].freeze

  belongs_to :source, polymorphic: true, optional: true
  belongs_to :project
  belongs_to :user
  has_many :run_events,
           class_name: 'AutomyraBridgeRunEvent',
           dependent: :destroy

  validates :source_type, :source_id, :project, :user, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[queued running retrying]) }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }

  def mark_running!
    update!(status: 'running', started_at: started_at || Time.current, finished_at: nil)
  end

  def mark_retrying!
    update!(status: 'retrying', finished_at: nil)
  end

  def mark_failed!(attrs = {})
    update!(attrs.merge(status: 'failed', finished_at: Time.current))
  end

  def mark_completed!(attrs = {})
    update!(attrs.merge(status: 'completed', finished_at: Time.current))
  end
end
