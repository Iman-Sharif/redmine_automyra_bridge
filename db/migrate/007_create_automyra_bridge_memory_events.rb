class CreateAutomyraBridgeMemoryEvents < ActiveRecord::Migration[6.1]
  def change
    return if table_exists?(:automyra_bridge_memory_events)

    create_table :automyra_bridge_memory_events do |t|
      t.string :container_type, null: false
      t.integer :container_id, null: false
      t.references :user, null: true, index: { name: 'idx_automyra_memory_user' }
      t.string :role, null: false
      t.string :event_type, null: false
      t.text :content
      t.text :payload
      t.string :correlation_id
      t.integer :journal_id
      t.timestamps
    end

    add_index :automyra_bridge_memory_events,
      %i[container_type container_id created_at],
      name: 'idx_automyra_memory_container_time'
    add_index :automyra_bridge_memory_events, :correlation_id, name: 'idx_automyra_memory_correlation'
    add_index :automyra_bridge_memory_events, :journal_id, name: 'idx_automyra_memory_journal'
  end
end
