require File.expand_path('../test_helper', __dir__)

class WikiHubGraphTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageLink.delete_all
    create_snapshot(6401, 6201, 'Master Playbook')
    create_snapshot(6402, 6203, 'Supplier Onboarding')
    create_snapshot(6403, 6202, 'Contract Boilerplate')

    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6402, target_project_id: 6203, target_title: 'Supplier Onboarding', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6403, target_page_id: nil, target_project_id: 6202, target_title: 'Missing', resolved: false, link_type: 'wiki')
  end

  test 'graph route resolves to graph index action' do
    route = Rails.application.routes.recognize_path('/knowledge_hub/graph.json', method: :get)

    assert_equal 'wiki_hub_graph', route.fetch(:controller)
    assert_equal 'index', route.fetch(:action)
    assert_equal 'json', route.fetch(:format)
  end

  test 'visible graph edges include only resolved links' do
    user = User.find_by!(login: 'hub_admin')
    edges = visible_edges_for(user)

    assert edges.any?
    assert_equal 2, edges.size
    assert edges.none? { |edge| edge.target_page_id.nil? }
  end

  test 'graph edges are permission filtered by target project' do
    user = User.find_by!(login: 'hub_reader_a')
    edges = visible_edges_for(user)

    assert_equal ['Contract Boilerplate'], edges.map(&:target_title)
    assert_not_includes edges.map(&:target_title), 'Supplier Onboarding'
  end

  test 'graph nodes for hub_no_wiki are empty' do
    user = User.find_by!(login: 'hub_no_wiki')

    assert_equal [], visible_nodes_for(user)
  end

  private

  def create_snapshot(wiki_page_id, project_id, title)
    WikiHub::PageSnapshot.create!(wiki_page_id: wiki_page_id, project_id: project_id, title: title, searchable_text: title)
  end

  def visible_edges_for(user)
    visible_project_ids = WikiHub::PageUniverseService.new(user).visible_pages.distinct.pluck(:project_id)
    WikiHub::PageLink.where(resolved: true, target_project_id: visible_project_ids).order(:target_title)
  end

  def visible_nodes_for(user)
    WikiHub::PageUniverseService.new(user).visible_pages.order(:title).pluck(:title)
  end
end

class WikiHubGraphControllerTest < ActionController::TestCase
  tests WikiHubGraphController

  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageLink.delete_all
    WikiHub::PageProfile.delete_all

    WikiHub::PageSnapshot.create!(wiki_page_id: 6402, project_id: 6203, title: 'Supplier Onboarding', searchable_text: 'Supplier Onboarding')
    WikiHub::PageSnapshot.create!(wiki_page_id: 6403, project_id: 6202, title: 'Contract Boilerplate', searchable_text: 'Contract Boilerplate')
    WikiHub::PageLink.create!(source_page_id: 6402, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
  end

  test 'graph hides inaccessible root pages' do
    login_as('hub_reader_a')
    as_json!

    get :index, params: { root_page_id: 6402 }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal [], body.fetch('nodes')
    assert_equal [], body.fetch('edges')
  end

  test 'graph response includes private cache headers' do
    login_as('hub_admin')
    as_json!

    get :index, params: { root_page_id: 6402 }
    assert_response :success

    # Verify cache headers are set (private, 5 minute TTL)
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
