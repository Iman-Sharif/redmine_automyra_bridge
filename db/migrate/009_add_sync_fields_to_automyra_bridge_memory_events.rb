class AddSyncFieldsToAutomyraBridgeMemoryEvents < ActiveRecord::Migration[6.1]
  def change
    return unless table_exists?(:automyra_bridge_memory_events)

    add_column :automyra_bridge_memory_events, :sync_status, :string, null: false, default: 'pending' unless column_exists?(:automyra_bridge_memory_events, :sync_status)
    add_column :automyra_bridge_memory_events, :sync_error, :text unless column_exists?(:automyra_bridge_memory_events, :sync_error)
    add_column :automyra_bridge_memory_events, :external_memory_id, :string unless column_exists?(:automyra_bridge_memory_events, :external_memory_id)
    add_index :automyra_bridge_memory_events, :sync_status, name: 'idx_automyra_memory_sync_status' unless index_exists?(:automyra_bridge_memory_events, :sync_status, name: 'idx_automyra_memory_sync_status')
    add_index :automyra_bridge_memory_events, :external_memory_id, name: 'idx_automyra_memory_external_id' unless index_exists?(:automyra_bridge_memory_events, :external_memory_id, name: 'idx_automyra_memory_external_id')
  end
end
