namespace :wiki_hub do
  task :migrate_plugin_schema do
    next unless Rake::Task.task_defined?('redmine:plugins:migrate')
    next if ActiveRecord::Base.connection.data_source_exists?('wiki_hub_page_snapshots')

    previous_name = ENV['NAME']
    ENV['NAME'] = 'redmine_wiki_hub'

    begin
      task = Rake::Task['redmine:plugins:migrate']
      task.reenable
      task.invoke
    ensure
      ENV['NAME'] = previous_name
    end
  end
end

if Rake::Task.task_defined?('db:migrate')
  Rake::Task['db:migrate'].enhance do
    Rake::Task['wiki_hub:migrate_plugin_schema'].invoke
  end
end
