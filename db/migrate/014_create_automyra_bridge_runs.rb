class CreateAutomyraBridgeRuns < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_runs)

    create_table :automyra_bridge_runs do |t|
      t.integer :source_id, null: false
      t.string :source_type, null: false
      t.text :context_snapshot
      t.text :response_snapshot
      t.text :tool_calls
      t.text :proposals
      t.string :status, null: false, default: 'queued'
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :user_id, null: false
      t.integer :project_id, null: false
      t.text :llm_calls
      t.text :total_tokens
      t.timestamps
    end

    add_index :automyra_bridge_runs, %i[source_type source_id], unique: true, name: 'idx_automyra_runs_source'
    add_index :automyra_bridge_runs, %i[status created_at], name: 'idx_automyra_runs_status_created'
    add_index :automyra_bridge_runs, :user_id unless index_exists?(:automyra_bridge_runs, :user_id)
    add_index :automyra_bridge_runs, :project_id unless index_exists?(:automyra_bridge_runs, :project_id)
  end

  def down
    drop_table :automyra_bridge_runs if table_exists?(:automyra_bridge_runs)
  end
end
