$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
begin
  require 'mocha/minitest'
rescue LoadError
end

require File.expand_path('../../../test/test_helper', __dir__)

module RedmineWikiHub
  module PluginFixturesLoader
    def plugin_fixture_path
      File.join(__dir__, 'fixtures')
    end

    def fixtures(*table_names)
      return super if table_names.first == :all

      table_names.each do |table_name|
        fixture_file = File.join(plugin_fixture_path, "#{table_name}.yml")
        ActiveRecord::FixtureSet.create_fixtures(plugin_fixture_path, table_name) if File.exist?(fixture_file)
      end

      super
    end

    def redmine_fixtures_list
      %i[
        users groups_users user_preferences email_addresses roles enumerations auth_sources tokens enabled_modules
        projects projects_trackers members member_roles news
        issues issue_statuses issue_categories issue_relations journals journal_details watchers attachments
        custom_fields custom_values custom_fields_projects custom_fields_trackers
        versions trackers workflows time_entries repositories changesets changes
        wikis wiki_pages wiki_contents wiki_content_versions queries
      ]
    end

    def plugin_fixtures_list
      %i[users projects roles enabled_modules members member_roles wikis wiki_pages wiki_contents]
    end

    def fixtures_list
      redmine_fixtures_list + plugin_fixtures_list
    end
  end

  class TestCase < ActiveSupport::TestCase
    extend PluginFixturesLoader

    fixtures(*fixtures_list)
  end
end
