class CreateAutomyraBridgeGovernanceActions < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_governance_actions)

    create_table :automyra_bridge_governance_actions do |t|
      t.integer :governance_run_id, null: false
      t.integer :governance_finding_id, null: false
      t.integer :governance_policy_id, null: false
      t.string :action_type, null: false
      t.string :object_type, null: false
      t.integer :object_id, null: false
      t.text :before_value
      t.text :after_value
      t.text :rollback_payload
      t.string :idempotency_key
      t.string :status, null: false, default: 'pending'
      t.datetime :applied_at
      t.datetime :rolled_back_at
      t.integer :created_by_id
      t.timestamps
    end

    add_index :automyra_bridge_governance_actions, :governance_run_id, name: 'idx_automyra_gov_actions_run'
    add_index :automyra_bridge_governance_actions, :governance_finding_id, name: 'idx_automyra_gov_actions_finding'
    add_index :automyra_bridge_governance_actions, :governance_policy_id, name: 'idx_automyra_gov_actions_policy'
    add_index :automyra_bridge_governance_actions, %i[object_type object_id], name: 'idx_automyra_gov_actions_object'
    add_index :automyra_bridge_governance_actions, :status, name: 'idx_automyra_gov_actions_status'
    add_index :automyra_bridge_governance_actions, :idempotency_key, unique: true, name: 'idx_automyra_gov_actions_idempotency'
  end

  def down
    drop_table :automyra_bridge_governance_actions if table_exists?(:automyra_bridge_governance_actions)
  end
end
