require File.expand_path('../integration_test_helper', __dir__)

class WikiHubLandingTest < RedmineWikiHub::IntegrationTest
  test 'anonymous user is redirected from landing page' do
    get '/knowledge_hub'

    assert_response :redirect
    assert_match '/login', response.location
  end

  test 'landing route resolves to wiki_hub index' do
    route = Rails.application.routes.recognize_path('/knowledge_hub', method: :get)

    assert_equal 'wiki_hub', route.fetch(:controller)
    assert_equal 'index', route.fetch(:action)
  end

  test 'project landing route resolves to project_index' do
    route = Rails.application.routes.recognize_path('/projects/procurement-kb/wiki_hub', method: :get)

    assert_equal 'wiki_hub', route.fetch(:controller)
    assert_equal 'project_index', route.fetch(:action)
    assert_equal 'procurement-kb', route.fetch(:project_id)
  end

  test 'project search route resolves to project_search action' do
    route = Rails.application.routes.recognize_path('/projects/procurement-kb/wiki_hub/search', method: :get)

    assert_equal 'wiki_hub', route.fetch(:controller)
    assert_equal 'project_search', route.fetch(:action)
    assert_equal 'procurement-kb', route.fetch(:project_id)
  end
end
