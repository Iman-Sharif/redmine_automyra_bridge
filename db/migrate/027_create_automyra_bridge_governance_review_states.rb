class CreateAutomyraBridgeGovernanceReviewStates < ActiveRecord::Migration[7.2]
  def change
    create_table :automyra_bridge_governance_review_states do |t|
      t.references :governance_policy, null: false, foreign_key: { to_table: :automyra_bridge_governance_policies }, index: { name: 'idx_automyra_gov_review_states_policy' }
      t.references :governance_run, null: false, foreign_key: { to_table: :automyra_bridge_governance_runs }, index: { name: 'idx_automyra_gov_review_states_run' }
      t.string :object_type, null: false
      t.integer :object_id, null: false
      t.string :review_domain, null: false
      t.string :content_fingerprint, null: false
      t.string :policy_source_hash, null: false
      t.datetime :last_reviewed_at, null: false

      t.timestamps null: false
    end

    add_index :automyra_bridge_governance_review_states,
              %i[governance_policy_id object_type object_id review_domain],
              unique: true,
              name: 'idx_automyra_gov_review_states_lookup'
  end
end
