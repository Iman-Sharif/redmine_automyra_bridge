require File.expand_path('../test_helper', __dir__)

class WikiHubAdminTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::IndexRun.delete_all
  end

  test 'healthcheck returns structured payload' do
    health = WikiHub::Healthcheck.call

    assert_includes %w[ok error], health.fetch(:status)
    assert_kind_of Hash, health.fetch(:details)
    assert health.fetch(:details).key?(:errors)
  end

  test 'rebuild_all returns index run id and processed count' do
    result = WikiHub::Indexer.rebuild_all(batch_size: 2)

    assert result[:index_run_id].present?
    assert_equal WikiPage.count, result[:pages_processed]
  end

  test 'successful rebuild updates healthcheck recent successful run' do
    WikiHub::Indexer.rebuild_all(batch_size: 2)

    health = WikiHub::Healthcheck.call
    assert_equal 'ok', health.fetch(:status)
    assert_not_nil health.fetch(:details).fetch(:recent_successful_index_run_at)
  end

  test 'admin health and rebuild routes resolve correctly' do
    health = Rails.application.routes.recognize_path('/admin/wiki_hub/health', method: :get)
    rebuild = Rails.application.routes.recognize_path('/admin/wiki_hub/rebuild', method: :post)

    assert_equal 'wiki_hub_admin', health.fetch(:controller)
    assert_equal 'health', health.fetch(:action)
    assert_equal 'wiki_hub_admin', rebuild.fetch(:controller)
    assert_equal 'rebuild', rebuild.fetch(:action)
  end
end

class WikiHubAdminControllerTest < ActionController::TestCase
  tests WikiHubAdminController

  test 'non admin cannot access health or rebuild' do
    login_as('hub_reader_a')
    as_json!

    get :health
    assert_response :forbidden

    post :rebuild
    assert_response :forbidden
  end

  test 'admin can access health payload' do
    login_as('hub_admin')
    as_json!

    get :health
    assert_response :success
    assert JSON.parse(response.body).key?('status')
  end

  test 'admin can trigger rebuild payload' do
    login_as('hub_admin')
    as_json!

    post :rebuild
    assert_response :success
    assert JSON.parse(response.body).key?('index_run_id')
  end

  private

  def login_as(login)
    user = User.find_by!(login: login)
    @request.session[:user_id] = user.id
    User.current = user
  end

  def as_json!
    @request.accept = 'application/json'
    @request.content_type = 'application/json'
  end
end
