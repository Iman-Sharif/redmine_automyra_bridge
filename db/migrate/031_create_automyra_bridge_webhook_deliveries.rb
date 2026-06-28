class CreateAutomyraBridgeWebhookDeliveries < ActiveRecord::Migration[6.1]
  def change
    create_table :automyra_bridge_webhook_deliveries do |t|
      t.string :event_type, null: false
      t.string :delivery_id, null: false
      t.text :payload, null: false
      t.string :target_type
      t.integer :target_id
      t.integer :project_id
      t.integer :source_journal_id
      t.integer :fallback_journal_id
      t.integer :retry_count, null: false, default: 0
      t.integer :max_retries, null: false, default: 3
      t.datetime :next_retry_at, null: false
      t.string :status, null: false, default: 'pending'
      t.text :last_error
      t.integer :detected_journal_id
      t.string :detection_method
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :automyra_bridge_webhook_deliveries, :delivery_id,
              unique: true, name: 'idx_automyra_bridge_webhook_deliveries_delivery_id'
    add_index :automyra_bridge_webhook_deliveries, %i[status next_retry_at],
              name: 'idx_automyra_bridge_webhook_deliveries_status_next_retry'
    add_index :automyra_bridge_webhook_deliveries, %i[target_type target_id status],
              name: 'idx_automyra_bridge_webhook_deliveries_target_status'
    add_index :automyra_bridge_webhook_deliveries, %i[project_id created_at],
              name: 'idx_automyra_bridge_webhook_deliveries_project_created'
  end
end