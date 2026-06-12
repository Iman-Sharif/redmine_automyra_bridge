class AddValuesToAutomyraBridgeGovernanceActions < ActiveRecord::Migration[6.1]
  def up
    add_column :automyra_bridge_governance_actions, :before_value, :text unless column_exists?(:automyra_bridge_governance_actions, :before_value)
    add_column :automyra_bridge_governance_actions, :after_value, :text unless column_exists?(:automyra_bridge_governance_actions, :after_value)
  end

  def down
    remove_column :automyra_bridge_governance_actions, :before_value if column_exists?(:automyra_bridge_governance_actions, :before_value)
    remove_column :automyra_bridge_governance_actions, :after_value if column_exists?(:automyra_bridge_governance_actions, :after_value)
  end
end
