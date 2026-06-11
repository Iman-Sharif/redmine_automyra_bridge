class AddOperatorFieldsToAutomyraBridgeJobs < ActiveRecord::Migration[6.1]
  def change
    return unless table_exists?(:automyra_bridge_jobs)

    add_column :automyra_bridge_jobs, :attempts, :integer, null: false, default: 0 unless column_exists?(:automyra_bridge_jobs, :attempts)
  end
end
