class CreateAutomyraBridgeActionProposals < ActiveRecord::Migration[6.1]
  def change
    return if table_exists?(:automyra_bridge_action_proposals)

    create_table :automyra_bridge_action_proposals do |t|
      t.references :automyra_bridge_job, null: false, index: { name: 'idx_automyra_proposals_job' }
      t.references :project, null: false
      t.references :task, null: true, index: { name: 'idx_automyra_proposals_task' }
      t.references :user, null: false
      t.references :approved_by, null: true
      t.string :action_type, null: false
      t.string :status, null: false, default: 'pending'
      t.text :request_payload
      t.text :result_payload
      t.text :error_message
      t.string :idempotency_key
      t.datetime :decided_at
      t.datetime :executed_at
      t.timestamps
    end

    add_index :automyra_bridge_action_proposals, :status, name: 'idx_automyra_proposals_status'
    add_index :automyra_bridge_action_proposals, %i[task_id status], name: 'idx_automyra_proposals_task_status'
    add_index :automyra_bridge_action_proposals, :idempotency_key, unique: true, name: 'idx_automyra_proposals_idempotency'
  end
end
