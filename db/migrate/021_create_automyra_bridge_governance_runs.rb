class CreateAutomyraBridgeGovernanceRuns < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_governance_runs)

    create_table :automyra_bridge_governance_runs do |t|
      t.integer :governance_policy_id, null: false
      t.string :status, null: false, default: 'queued'
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :findings_count, default: 0
      t.integer :actions_count, default: 0
      t.integer :applied_count, default: 0
      t.text :error_message
      t.string :policy_source_hash
      t.string :provider_model_used
      t.string :prompt_hash
      t.string :response_hash
      t.integer :max_changes_allowed
      t.integer :created_by_id
      t.timestamps
    end

    add_index :automyra_bridge_governance_runs, :governance_policy_id, name: 'idx_automyra_gov_runs_policy'
    add_index :automyra_bridge_governance_runs, %i[status created_at], name: 'idx_automyra_gov_runs_status_created'
    add_index :automyra_bridge_governance_runs, :created_by_id, name: 'idx_automyra_gov_runs_created_by'
  end

  def down
    drop_table :automyra_bridge_governance_runs if table_exists?(:automyra_bridge_governance_runs)
  end
end
