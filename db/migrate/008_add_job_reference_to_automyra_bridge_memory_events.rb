class AddJobReferenceToAutomyraBridgeMemoryEvents < ActiveRecord::Migration[6.1]
  def change
    return unless table_exists?(:automyra_bridge_memory_events)
    return if column_exists?(:automyra_bridge_memory_events, :job_id)

    add_reference :automyra_bridge_memory_events,
      :job,
      null: true,
      index: { name: 'idx_automyra_memory_job' }
  end
end
