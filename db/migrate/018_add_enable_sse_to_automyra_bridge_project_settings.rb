class AddEnableSseToAutomyraBridgeProjectSettings < ActiveRecord::Migration[6.1]
  def change
    return unless table_exists?(:automyra_bridge_project_settings)
    return if column_exists?(:automyra_bridge_project_settings, :enable_sse)

    add_column :automyra_bridge_project_settings, :enable_sse, :boolean, null: false, default: false
  end
end
