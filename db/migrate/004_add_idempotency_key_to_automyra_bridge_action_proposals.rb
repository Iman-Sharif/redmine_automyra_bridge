class AddIdempotencyKeyToAutomyraBridgeActionProposals < ActiveRecord::Migration[6.1]
  def change
    return unless table_exists?(:automyra_bridge_action_proposals)
    return if column_exists?(:automyra_bridge_action_proposals, :idempotency_key)

    add_column :automyra_bridge_action_proposals, :idempotency_key, :string
    add_index :automyra_bridge_action_proposals,
              :idempotency_key,
              unique: true,
              name: 'idx_automyra_proposals_idempotency'
  end
end
