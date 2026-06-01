require File.expand_path('test_helper', __dir__)

module RedmineWikiHub
  class IntegrationTest < Redmine::IntegrationTest
    extend PluginFixturesLoader

    fixtures(*fixtures_list)
  end
end
