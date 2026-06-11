class CreateAutomyraBridgeRunEvents < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_run_events)

    create_table :automyra_bridge_run_events do |t|
      t.integer :automyra_bridge_run_id, null: false
      t.integer :sequence, null: false
      t.string :event_type, null: false
      t.string :status
      t.string :role
      t.text :message
      t.text :payload
      t.boolean :visible_to_user, default: true
      t.integer :created_by_id
      t.datetime :created_at
    end

    add_index :automyra_bridge_run_events, :automyra_bridge_run_id
    add_index :automyra_bridge_run_events,
              %i[automyra_bridge_run_id sequence],
              unique: true,
              name: 'idx_automyra_run_events_run_sequence'
    add_index :automyra_bridge_run_events,
              %i[automyra_bridge_run_id id],
              name: 'idx_automyra_run_events_run_id'
    add_index :automyra_bridge_run_events, :created_at
  end

  def down
    drop_table :automyra_bridge_run_events if table_exists?(:automyra_bridge_run_events)
  end
end
