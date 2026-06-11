module AutomyraBridge
  class GovernanceAction < ActiveRecord::Base
    self.table_name = 'automyra_bridge_governance_actions'

    STATUSES = %w[pending validated proposed applied failed rolled_back].freeze

    belongs_to :governance_run, class_name: 'AutomyraBridge::GovernanceRun'
    belongs_to :governance_finding, class_name: 'AutomyraBridge::GovernanceFinding'
    belongs_to :governance_policy, class_name: 'AutomyraBridge::GovernancePolicy'
    belongs_to :created_by, class_name: 'User', optional: true

    validates :governance_run, :governance_finding, :governance_policy, :action_type, :object_type, :object_id, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :idempotency_key, uniqueness: true, allow_blank: true


    scope :pending, -> { where(status: 'pending') }
    scope :validated, -> { where(status: 'validated') }
    scope :proposed, -> { where(status: 'proposed') }
    scope :applied, -> { where(status: 'applied') }
    scope :failed, -> { where(status: 'failed') }
    scope :rolled_back, -> { where(status: 'rolled_back') }
    scope :for_object, ->(object) { where(object_type: object.class.name, object_id: object.id) }

    STATUSES.each do |action_status|
      define_method("#{action_status}?") { status.to_s == action_status }
    end

    def mark_validated!(attrs = {})
      update!(attrs.merge(status: 'validated'))
    end

    def mark_proposed!(attrs = {})
      update!(attrs.merge(status: 'proposed'))
    end

    def mark_applied!(attrs = {})
      update!(attrs.merge(status: 'applied', applied_at: Time.current))
    end

    def mark_failed!(attrs = {})
      update!(attrs.merge(status: 'failed'))
    end


  end
end
