class AddGlobalScopeToAutomyraBridgeGovernancePolicies < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:automyra_bridge_governance_policies)

    add_column :automyra_bridge_governance_policies, :scope_type, :string, null: false, default: 'project' unless column_exists?(:automyra_bridge_governance_policies, :scope_type)
    change_column_null :automyra_bridge_governance_policies, :project_id, true
    add_index :automyra_bridge_governance_policies, :scope_type, name: 'idx_automyra_gov_policies_scope_type' unless index_exists?(:automyra_bridge_governance_policies, :scope_type, name: 'idx_automyra_gov_policies_scope_type')
  end

  def down
    return unless table_exists?(:automyra_bridge_governance_policies)

    AutomyraBridge::GovernancePolicy.where(project_id: nil).delete_all if defined?(AutomyraBridge::GovernancePolicy)
    change_column_null :automyra_bridge_governance_policies, :project_id, false
    remove_index :automyra_bridge_governance_policies, name: 'idx_automyra_gov_policies_scope_type' if index_exists?(:automyra_bridge_governance_policies, :scope_type, name: 'idx_automyra_gov_policies_scope_type')
    remove_column :automyra_bridge_governance_policies, :scope_type if column_exists?(:automyra_bridge_governance_policies, :scope_type)
  end
end
