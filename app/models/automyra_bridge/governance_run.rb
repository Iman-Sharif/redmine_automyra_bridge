module AutomyraBridge
  class GovernanceRun < ActiveRecord::Base
    self.table_name = 'automyra_bridge_governance_runs'

    STATUSES = %w[queued running completed failed cancelled].freeze

    belongs_to :governance_policy, class_name: 'AutomyraBridge::GovernancePolicy'
    belongs_to :created_by, class_name: 'User', optional: true
    has_many :governance_findings, class_name: 'AutomyraBridge::GovernanceFinding', dependent: :destroy
    has_many :governance_actions, class_name: 'AutomyraBridge::GovernanceAction', dependent: :destroy
    has_many :governance_review_states, class_name: 'AutomyraBridge::GovernanceReviewState', dependent: :destroy

    validates :governance_policy, :status, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :queued, -> { where(status: 'queued') }
    scope :running, -> { where(status: 'running') }
    scope :completed, -> { where(status: 'completed') }
    scope :failed, -> { where(status: 'failed') }
    scope :cancelled, -> { where(status: 'cancelled') }
    scope :active, -> { where(status: %w[queued running]) }

    STATUSES.each do |run_status|
      define_method("#{run_status}?") { status.to_s == run_status }
    end

    def mark_running!
      update!(status: 'running', started_at: started_at || Time.current, finished_at: nil)
    end

    def mark_completed!(attrs = {})
      update!(attrs.merge(status: 'completed', finished_at: Time.current))
    end

    def mark_failed!(attrs = {})
      update!(attrs.merge(status: 'failed', finished_at: Time.current))
    end

    def mark_cancelled!(attrs = {})
      update!(attrs.merge(status: 'cancelled', finished_at: Time.current))
    end
  end
end
