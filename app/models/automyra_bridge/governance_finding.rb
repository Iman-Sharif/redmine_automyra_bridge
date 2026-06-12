module AutomyraBridge
  class GovernanceFinding < ApplicationRecord
    self.table_name = 'automyra_bridge_governance_findings'

    FINDING_TYPES = %w[
      wiki_title task_title attachment_filename wiki_requirement_link task_requirement_link
      wiki_summary wiki_metadata wiki_heading_structure
    ].freeze
    STATUSES = %w[pending valid invalid applied rejected].freeze

    belongs_to :governance_run, class_name: 'AutomyraBridge::GovernanceRun'
    belongs_to :governance_policy, class_name: 'AutomyraBridge::GovernancePolicy'
    belongs_to :created_by, class_name: 'User', optional: true
    has_many :governance_actions, class_name: 'AutomyraBridge::GovernanceAction', dependent: :destroy

    validates :governance_run, :governance_policy, :object_type, :object_id, :finding_type, :status, presence: true
    validates :finding_type, inclusion: { in: FINDING_TYPES }
    validates :status, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: 'pending') }
    scope :valid, -> { where(status: 'valid') }
    scope :invalid, -> { where(status: 'invalid') }
    scope :applied, -> { where(status: 'applied') }
    scope :rejected, -> { where(status: 'rejected') }
    scope :for_object, ->(object) { where(object_type: object.class.name, object_id: object.id) }

    def pending?
      status.to_s == 'pending'
    end

    def valid_status?
      status.to_s == 'valid'
    end

    def invalid_status?
      status.to_s == 'invalid'
    end

    def applied?
      status.to_s == 'applied'
    end

    def rejected?
      status.to_s == 'rejected'
    end

    def mark_valid!(attrs = {})
      update!(attrs.merge(status: 'valid'))
    end

    def mark_invalid!(attrs = {})
      update!(attrs.merge(status: 'invalid'))
    end

    def mark_applied!(attrs = {})
      update!(attrs.merge(status: 'applied'))
    end

    def mark_rejected!(attrs = {})
      update!(attrs.merge(status: 'rejected'))
    end
  end
end
