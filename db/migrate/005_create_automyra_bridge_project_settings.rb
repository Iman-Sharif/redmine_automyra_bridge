class CreateAutomyraBridgeProjectSettings < ActiveRecord::Migration[6.1]
  def change
    return if table_exists?(:automyra_bridge_project_settings)

    create_table :automyra_bridge_project_settings do |t|
      t.integer :project_id, null: false
      t.string :enabled_actions, null: false, default: 'create_task,update_task'
      t.string :risk_tier, null: false, default: 'approval_required'
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :automyra_bridge_project_settings,
              :project_id,
              unique: true,
              name: 'idx_automyra_project_settings_project'
  end
end
