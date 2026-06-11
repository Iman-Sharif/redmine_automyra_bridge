class CreateAutomyraBridgeAuditEvents < ActiveRecord::Migration[6.1]
  def change
    create_table :automyra_bridge_audit_events do |t|
      t.integer :user_id, null: false
      t.integer :project_id
      t.string :action, null: false
      t.string :correlation_id, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false
      t.text :request_payload
      t.text :response_payload
      t.text :error_message
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :automyra_bridge_audit_events, :correlation_id, unique: true, name: 'idx_automyra_audit_correlation'
    add_index :automyra_bridge_audit_events, :idempotency_key, unique: true, name: 'idx_automyra_audit_idempotency'
    add_index :automyra_bridge_audit_events, %i[user_id created_at], name: 'idx_automyra_audit_user_created'
  end
end
