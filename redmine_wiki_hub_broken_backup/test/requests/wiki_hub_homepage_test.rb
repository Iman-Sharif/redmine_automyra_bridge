require File.expand_path('../test_helper', __dir__)

class WikiHubHomepageControllerTest < ActionController::TestCase
  tests WikiHubHomepageController

  test 'homepage preference requires login' do
    get :show
    assert_response :redirect
  end

  test 'homepage preference updates current user only' do
    login_as('hub_reader_a')
    as_json!

    patch :update, params: { homepage_enabled: '1' }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body.fetch('homepage_enabled')
    assert_equal true, WikiHub::UserPreference.find_by!(user_id: User.find_by!(login: 'hub_reader_a').id).homepage_enabled
  end

  test 'homepage show renders persisted status for current user preference' do
    user = User.find_by!(login: 'hub_reader_a')
    WikiHub::UserPreference.where(user_id: user.id).delete_all
    WikiHub::UserPreference.create!(user_id: user.id, homepage_enabled: true)

    login_as('hub_reader_a')
    get :show

    assert_response :success
    assert_includes response.body, 'wiki-hub-homepage-status'
    assert_includes response.body, 'wiki-hub-status-enabled'
  end

  test 'homepage update accepts opt_in alias and keeps other users unchanged' do
    reader_a = User.find_by!(login: 'hub_reader_a')
    reader_b = User.find_by!(login: 'hub_reader_b')
    WikiHub::UserPreference.where(user_id: [reader_a.id, reader_b.id]).delete_all
    WikiHub::UserPreference.create!(user_id: reader_b.id, homepage_enabled: false)

    login_as('hub_reader_a')
    as_json!
    patch :update, params: { opt_in: 'true' }

    assert_response :success
    assert_equal true, WikiHub::UserPreference.find_by!(user_id: reader_a.id).homepage_enabled
    assert_equal false, WikiHub::UserPreference.find_by!(user_id: reader_b.id).homepage_enabled
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
