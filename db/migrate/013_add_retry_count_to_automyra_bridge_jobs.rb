class AddRetryCountToAutomyraBridgeJobs < ActiveRecord::Migration[6.1]
  def change
    return unless table_exists?(:automyra_bridge_jobs)

    add_column :automyra_bridge_jobs, :retry_count, :integer, null: false, default: 0 unless column_exists?(:automyra_bridge_jobs, :retry_count)
    add_column :automyra_bridge_jobs, :max_retries, :integer, null: false, default: 3 unless column_exists?(:automyra_bridge_jobs, :max_retries)
    add_column :automyra_bridge_jobs, :backoff_seconds, :integer, null: false, default: 0 unless column_exists?(:automyra_bridge_jobs, :backoff_seconds)
  end
end
