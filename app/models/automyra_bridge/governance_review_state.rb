module AutomyraBridge
  class GovernanceReviewState < ActiveRecord::Base
    self.table_name = 'automyra_bridge_governance_review_states'

    belongs_to :governance_policy, class_name: 'AutomyraBridge::GovernancePolicy'
    belongs_to :governance_run, class_name: 'AutomyraBridge::GovernanceRun'

    validates :governance_policy, :governance_run, :object_type, :object_id, :review_domain,
              :content_fingerprint, :policy_source_hash, :last_reviewed_at, presence: true
  end
end
