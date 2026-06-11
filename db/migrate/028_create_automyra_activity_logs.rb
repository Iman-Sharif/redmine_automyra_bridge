class CreateAutomyraActivityLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :automyra_activity_logs do |t|
      t.string :action_type, null: false
      t.string :source, null: false
      t.string :session_id
      t.string :target_type
      t.string :target_id
      t.integer :project_id
      t.integer :user_id
      t.text :summary, null: false
      t.jsonb :details
      t.string :idempotency_key, null: false
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :automyra_activity_logs, %i[action_type occurred_at], name: 'idx_automyra_logs_action_occurred'
    add_index :automyra_activity_logs, %i[project_id occurred_at], name: 'idx_automyra_logs_project_occurred'
    add_index :automyra_activity_logs, %i[source occurred_at], name: 'idx_automyra_logs_source_occurred'
    add_index :automyra_activity_logs, :idempotency_key, unique: true, name: 'idx_automyra_logs_idempotency'
  end
end
