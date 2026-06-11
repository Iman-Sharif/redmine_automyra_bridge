module AutomyraBridge
  class GovernancePolicy < ActiveRecord::Base
    self.table_name = 'automyra_bridge_governance_policies'

    MODES = %w[report_only propose apply_after_validation].freeze
    SCOPE_TYPES = %w[project global].freeze

    belongs_to :project, optional: true
    belongs_to :policy_page, class_name: 'WikiHub::PageProfile', optional: true
    belongs_to :created_by, class_name: 'User', optional: true
    has_many :governance_runs, class_name: 'AutomyraBridge::GovernanceRun', dependent: :destroy
    has_many :governance_findings, class_name: 'AutomyraBridge::GovernanceFinding', dependent: :destroy
    has_many :governance_actions, class_name: 'AutomyraBridge::GovernanceAction', dependent: :destroy
    has_many :governance_review_states, class_name: 'AutomyraBridge::GovernanceReviewState', dependent: :destroy

    validates :name, :mode, :provider_model, presence: true
    validates :mode, inclusion: { in: MODES }
    validates :scope_type, inclusion: { in: SCOPE_TYPES }
    validates :enabled, inclusion: { in: [true, false] }
    validates :project, presence: true, if: :project_scope?

    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :report_only, -> { where(mode: 'report_only') }
    scope :propose, -> { where(mode: 'propose') }
    scope :apply_after_validation, -> { where(mode: 'apply_after_validation') }

    MODES.each do |policy_mode|
      define_method("#{policy_mode}?") { mode.to_s == policy_mode }
    end

    def project_scope?
      scope_type.to_s == 'project'
    end

    def global?
      scope_type.to_s == 'global'
    end

    def mark_ran!(time = Time.current)
      update!(last_run_at: time)
    end
  end
end
