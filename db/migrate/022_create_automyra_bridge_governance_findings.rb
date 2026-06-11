class CreateAutomyraBridgeGovernanceFindings < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_governance_findings)

    create_table :automyra_bridge_governance_findings do |t|
      t.integer :governance_run_id, null: false
      t.integer :governance_policy_id, null: false
      t.string :object_type, null: false
      t.integer :object_id, null: false
      t.string :finding_type, null: false
      t.text :current_value
      t.text :recommended_value
      t.decimal :confidence, precision: 5, scale: 4
      t.text :rationale
      t.string :status, null: false, default: 'pending'
      t.text :evaluator_error
      t.integer :created_by_id
      t.timestamps
    end

    add_index :automyra_bridge_governance_findings, :governance_run_id, name: 'idx_automyra_gov_findings_run'
    add_index :automyra_bridge_governance_findings, :governance_policy_id, name: 'idx_automyra_gov_findings_policy'
    add_index :automyra_bridge_governance_findings, %i[object_type object_id], name: 'idx_automyra_gov_findings_object'
    add_index :automyra_bridge_governance_findings, :status, name: 'idx_automyra_gov_findings_status'
    add_index :automyra_bridge_governance_findings, :finding_type, name: 'idx_automyra_gov_findings_type'
  end

  def down
    drop_table :automyra_bridge_governance_findings if table_exists?(:automyra_bridge_governance_findings)
  end
end
