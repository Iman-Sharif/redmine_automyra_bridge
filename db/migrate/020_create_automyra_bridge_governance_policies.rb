class CreateAutomyraBridgeGovernancePolicies < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_governance_policies)

    create_table :automyra_bridge_governance_policies do |t|
      t.string :name, null: false
      t.integer :project_id, null: false
      t.integer :policy_page_id
      t.text :config
      t.string :mode, null: false, default: 'report_only'
      t.string :provider_model, null: false, default: 'manifest/auto'
      t.integer :max_changes_per_run
      t.decimal :confidence_threshold, precision: 5, scale: 4
      t.integer :frequency_hours
      t.datetime :last_run_at
      t.boolean :enabled, default: true
      t.boolean :scope_wiki_pages, default: true
      t.boolean :scope_tasks, default: true
      t.boolean :scope_requirement_links, default: true
      t.boolean :scope_wiki_requirement_links, default: true
      t.boolean :scope_task_requirement_links, default: true
      t.text :exclusions
      t.integer :created_by_id
      t.timestamps
    end

    add_index :automyra_bridge_governance_policies, :project_id, name: 'idx_automyra_gov_policies_project'
    add_index :automyra_bridge_governance_policies, :policy_page_id, name: 'idx_automyra_gov_policies_page'
    add_index :automyra_bridge_governance_policies, :enabled, name: 'idx_automyra_gov_policies_enabled'
    add_index :automyra_bridge_governance_policies, :mode, name: 'idx_automyra_gov_policies_mode'
  end

  def down
    drop_table :automyra_bridge_governance_policies if table_exists?(:automyra_bridge_governance_policies)
  end
end
