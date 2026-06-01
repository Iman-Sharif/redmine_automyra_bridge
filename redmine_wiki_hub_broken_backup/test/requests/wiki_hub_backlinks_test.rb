require File.expand_path('../test_helper', __dir__)

class WikiHubBacklinksControllerTest < ActionController::TestCase
  tests WikiHubBacklinksController

  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageLink.delete_all

    WikiHub::PageSnapshot.create!(wiki_page_id: 6401, project_id: 6201, title: 'Master Playbook', searchable_text: 'Master Playbook')
    WikiHub::PageSnapshot.create!(wiki_page_id: 6402, project_id: 6203, title: 'Supplier Onboarding', searchable_text: 'Supplier Onboarding')
    WikiHub::PageSnapshot.create!(wiki_page_id: 6403, project_id: 6202, title: 'Contract Boilerplate', searchable_text: 'Contract Boilerplate')

    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6402, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
  end

  test 'backlinks omit hidden sources and hidden targets' do
    login_as('hub_reader_a')
    as_json!

    get :index, params: { page_id: 6403 }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal ['Master Playbook'], body.fetch('backlinks').map { |row| row.fetch('source_title') }

    get :index, params: { page_id: 6402 }
    assert_response :success
    hidden = JSON.parse(response.body)
    assert_nil hidden['target_page_id']
    assert_nil hidden['target_title']
    assert_equal [], hidden.fetch('backlinks')
  end

  test 'backlinks response includes private cache headers' do
    login_as('hub_admin')
    as_json!

    get :index, params: { page_id: 6403 }
    assert_response :success

    assert_includes response.headers['Cache-Control'], 'private'
    assert_includes response.headers['Cache-Control'], 'max-age=300'
    assert response.headers['Expires'].present?
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
