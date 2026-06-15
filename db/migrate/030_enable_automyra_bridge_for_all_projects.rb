class EnableAutomyraBridgeForAllProjects < ActiveRecord::Migration[6.1]
  def up
    module_name = 'automyra_bridge'

    execute <<-SQL.squish
      INSERT INTO enabled_modules (project_id, name)
      SELECT p.id, #{connection.quote(module_name)}
      FROM projects p
      WHERE NOT EXISTS (
        SELECT 1 FROM enabled_modules em
        WHERE em.project_id = p.id AND em.name = #{connection.quote(module_name)}
      )
    SQL

    default_modules = Setting[:default_projects_modules] || []
    unless default_modules.include?(module_name)
      Setting[:default_projects_modules] = default_modules + [module_name]
    end
  end

  def down
    module_name = 'automyra_bridge'

    default_modules = Setting[:default_projects_modules] || []
    Setting[:default_projects_modules] = default_modules - [module_name]

    execute "DELETE FROM enabled_modules WHERE name = #{connection.quote(module_name)}"
  end
end
