class AddScopeAttachmentsToAutomyraBridgeGovernancePolicies < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:automyra_bridge_governance_policies)

    return if column_exists?(:automyra_bridge_governance_policies, :scope_attachments)

    add_column :automyra_bridge_governance_policies, :scope_attachments, :boolean, null: false, default: false
  end

  def down
    return unless table_exists?(:automyra_bridge_governance_policies)

    remove_column :automyra_bridge_governance_policies, :scope_attachments if column_exists?(:automyra_bridge_governance_policies, :scope_attachments)
  end
end
