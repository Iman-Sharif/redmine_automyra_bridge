migration_root = if Dir.exist?('/opt/redmica/plugins/redmine_wiki_hub/db/migrate')
                   '/opt/redmica/plugins/redmine_wiki_hub/db/migrate'
                 else
                   File.expand_path('../../db/migrate', __dir__)
                 end

Dir[File.join(migration_root, '*.rb')].sort.each do |migration_file|
  load migration_file
end

def assert!(condition, message)
  raise message unless condition
end

def assert_raises(expected_class, expected_message)
  yield
  raise "expected #{expected_class} but nothing was raised"
rescue => error
  raise error unless error.is_a?(expected_class)
  raise "expected #{expected_message.inspect} in #{error.message.inspect}" unless error.message.include?(expected_message)
end

connection = ActiveRecord::Base.connection

assert!(connection.adapter_name == 'PostgreSQL', "expected PostgreSQL adapter, got #{connection.adapter_name}")
assert!(connection.database_version >= 160_000 && connection.database_version < 170_000,
        "expected PostgreSQL 16.x, got #{connection.database_version}")

expectations = {
  'CreateWikiHubPageSnapshots' => {
    table: :wiki_hub_page_snapshots,
    columns: %i[wiki_page_id project_id title searchable_text current_version_id created_at updated_at],
    indexes: %w[index_wiki_hub_page_snapshots_on_wiki_page_id index_wiki_hub_page_snapshots_on_project_id index_wiki_hub_page_snapshots_on_updated_at]
  },
  'CreateWikiHubPageLinks' => {
    table: :wiki_hub_page_links,
    columns: %i[source_page_id target_page_id target_project_id target_title resolved link_type created_at updated_at],
    indexes: %w[index_wiki_hub_page_links_on_source_page_id index_wiki_hub_page_links_on_target_page_id index_wiki_hub_page_links_on_target_project_id index_wiki_hub_page_links_on_resolved index_wiki_hub_page_links_on_created_at]
  },
  'CreateWikiHubPageProfiles' => {
    table: :wiki_hub_page_profiles,
    columns: %i[wiki_page_id page_kind category lesson_date summary featured created_at updated_at],
    indexes: %w[index_wiki_hub_page_profiles_on_wiki_page_id index_wiki_hub_page_profiles_on_page_kind index_wiki_hub_page_profiles_on_category]
  },
  'CreateWikiHubTags' => {
    table: :wiki_hub_tags,
    columns: %i[name created_at updated_at],
    indexes: %w[index_wiki_hub_tags_on_lower_name]
  },
  'CreateWikiHubTaggings' => {
    table: :wiki_hub_taggings,
    columns: %i[wiki_page_id tag_id created_at updated_at],
    indexes: %w[index_wiki_hub_taggings_on_wiki_page_id_and_tag_id index_wiki_hub_taggings_on_tag_id]
  },
  'CreateWikiHubUserPreferences' => {
    table: :wiki_hub_user_preferences,
    columns: %i[user_id homepage_enabled created_at updated_at],
    indexes: %w[index_wiki_hub_user_preferences_on_user_id]
  },
  'CreateWikiHubIndexRuns' => {
    table: :wiki_hub_index_runs,
    columns: %i[started_at completed_at status pages_processed error_message created_at updated_at],
    indexes: %w[index_wiki_hub_index_runs_on_status index_wiki_hub_index_runs_on_created_at]
  }
}

expectations.each do |class_name, expectation|
  class_name.constantize.new.migrate(:up)

  assert!(connection.table_exists?(expectation[:table]), "expected #{expectation[:table]} to exist")

  actual_columns = connection.columns(expectation[:table]).map { |column| column.name.to_sym }
  expectation[:columns].each do |column_name|
    assert!(actual_columns.include?(column_name), "expected #{expectation[:table]}.#{column_name} to exist")
  end

  actual_indexes = connection.indexes(expectation[:table]).map(&:name)
  expectation[:indexes].each do |index_name|
    assert!(actual_indexes.include?(index_name), "expected #{index_name} on #{expectation[:table]}")
  end
end

EnablePgTrgm.new.tap do |migration|
  2.times { migration.migrate(:up) }
end

assert!(connection.extension_enabled?('pg_trgm'), 'expected pg_trgm extension to be enabled')
assert!(connection.indexes(:wiki_hub_page_snapshots).map(&:name).include?('index_wiki_hub_page_snapshots_on_title_trgm'), 'expected snapshot trigram index to exist')
assert!(connection.indexes(:wiki_hub_page_links).map(&:name).include?('index_wiki_hub_page_links_on_target_title_trgm'), 'expected page links trigram index to exist')

EnablePgTrgm.new.tap do |migration|
  migration.define_singleton_method(:connection) { Struct.new(:adapter_name).new('Mysql2') }

  assert_raises(ActiveRecord::IrreversibleMigration, 'unsupported adapter') do
    migration.migrate(:up)
  end
end

EnablePgTrgm.new.tap do |migration|
  migration.define_singleton_method(:ensure_supported_postgresql16!) { |_context| true }
  migration.define_singleton_method(:table_exists?) { |_table_name| false }

  assert_raises(ActiveRecord::IrreversibleMigration, 'prerequisite tables are missing') do
    migration.migrate(:up)
  end
end

EnablePgTrgm.new.tap do |migration|
  migration.define_singleton_method(:ensure_supported_postgresql16!) { |_context| true }
  migration.define_singleton_method(:ensure_required_tables!) { true }
  migration.define_singleton_method(:column_exists?) { |_table_name, _column_name| false }

  assert_raises(ActiveRecord::IrreversibleMigration, 'prerequisite columns are missing') do
    migration.migrate(:up)
  end
end

puts 'plugin migration verification passed'
