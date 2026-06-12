class CreateAutomyraBridgeWebhookDeliveries < ActiveRecord::Migration[6.1]
  def change
    return if table_exists?(:automyra_bridge_webhook_deliveries)

    create_table :automyra_bridge_webhook_deliveries do |t|
      t.string :idempotency_key, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: 'delivered'
      t.datetime :delivered_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :automyra_bridge_webhook_deliveries,
              :idempotency_key,
              unique: true,
              name: 'idx_automyra_webhook_deliveries_idempotency'
  end
end
