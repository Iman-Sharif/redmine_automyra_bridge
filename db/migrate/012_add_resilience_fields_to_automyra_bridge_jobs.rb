class AddResilienceFieldsToAutomyraBridgeJobs < ActiveRecord::Migration[6.1]
  def change
    return unless table_exists?(:automyra_bridge_jobs)

    add_column :automyra_bridge_jobs, :retries, :integer, null: false, default: 0 unless column_exists?(:automyra_bridge_jobs, :retries)
    add_column :automyra_bridge_jobs, :max_retries, :integer, null: false, default: 3 unless column_exists?(:automyra_bridge_jobs, :max_retries)
    add_column :automyra_bridge_jobs, :backoff_seconds, :integer, null: false, default: 0 unless column_exists?(:automyra_bridge_jobs, :backoff_seconds)
    add_column :automyra_bridge_jobs, :last_heartbeat_at, :datetime unless column_exists?(:automyra_bridge_jobs, :last_heartbeat_at)
  end
end
