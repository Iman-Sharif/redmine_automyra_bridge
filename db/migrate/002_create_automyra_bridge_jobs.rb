class CreateAutomyraBridgeJobs < ActiveRecord::Migration[6.1]
  def change
    create_table :automyra_bridge_jobs do |t|
      t.string :status, null: false, default: 'queued'
      t.string :source_type, null: false
      t.integer :source_id, null: false
      t.integer :project_id, null: false
      t.integer :user_id, null: false
      t.string :correlation_id, null: false
      t.string :idempotency_key, null: false
      t.text :request_payload
      t.text :response_payload
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :automyra_bridge_jobs, :correlation_id, unique: true, name: 'idx_automyra_jobs_correlation'
    add_index :automyra_bridge_jobs, :idempotency_key, unique: true, name: 'idx_automyra_jobs_idempotency'
    add_index :automyra_bridge_jobs, %i[source_type source_id], unique: true, name: 'idx_automyra_jobs_source'
    add_index :automyra_bridge_jobs, %i[status created_at], name: 'idx_automyra_jobs_status_created'
  end
end
