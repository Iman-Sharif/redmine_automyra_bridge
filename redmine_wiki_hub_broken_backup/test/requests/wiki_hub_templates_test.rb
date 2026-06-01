require File.expand_path('../test_helper', __dir__)

class WikiHubTemplatesTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageProfile.delete_all
    WikiHub::Tagging.delete_all
    WikiHub::Tag.delete_all

    create_snapshot(6401, 6201, 'Master Playbook')
    create_snapshot(6403, 6202, 'Contract Boilerplate')
    create_snapshot(6404, 6201, 'Lessons 2026-04')

    WikiHub::PageProfile.create!(wiki_page_id: 6401, page_kind: 'standard', category: 'governance', featured: false)
    WikiHub::PageProfile.create!(wiki_page_id: 6403, page_kind: 'template', category: 'legal', featured: true)
    WikiHub::PageProfile.create!(wiki_page_id: 6404, page_kind: 'lesson_learned', category: 'operations', featured: false)

    tag = WikiHub::Tag.create!(name: 'contracts')
    WikiHub::Tagging.create!(wiki_page_id: 6403, tag_id: tag.id)
  end

  test 'page_kind filter returns only templates' do
    pages = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), page_kind: 'template').call

    assert_equal ['Contract Boilerplate'], pages.pluck(:title)
  end

  test 'category filter returns template in matching category' do
    pages = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), category: 'legal').call

    assert_equal ['Contract Boilerplate'], pages.pluck(:title)
  end

  test 'tag filter is case insensitive' do
    pages = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), tag: 'CONTRACTS').relation

    assert_equal ['Contract Boilerplate'], pages.pluck(:title)
  end

  test 'project scoped template query accepts project identifier' do
    pages = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), project_id: 'procurement-kb', page_kind: 'template').call

    assert_equal ['Contract Boilerplate'], pages.pluck(:title)
  end

  private

  def create_snapshot(wiki_page_id, project_id, title)
    WikiHub::PageSnapshot.create!(wiki_page_id: wiki_page_id, project_id: project_id, title: title, searchable_text: title)
  end
end

class WikiHubTemplatesControllerTest < ActionController::TestCase
  tests WikiHubTemplatesController

  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageProfile.delete_all
    WikiHub::PageLink.delete_all

    create_snapshot(6401, 6201, 'Master Playbook')
    create_snapshot(6402, 6203, 'Supplier Onboarding')
    create_snapshot(6403, 6202, 'Contract Boilerplate')

    WikiHub::PageProfile.create!(wiki_page_id: 6401, page_kind: 'standard', category: 'legal', featured: false)
    WikiHub::PageProfile.create!(wiki_page_id: 6402, page_kind: 'standard', category: 'legal', featured: false)
    WikiHub::PageProfile.create!(wiki_page_id: 6403, page_kind: 'template', category: 'legal', featured: true)

    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'template_usage')
    WikiHub::PageLink.create!(source_page_id: 6402, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'template_usage')
  end

  test 'hidden template surfaces return not found' do
    login_as('hub_reader_b')
    as_json!

    post :preview, params: { id: 6403, variables: { 'name' => 'Reader' } }
    assert_response :not_found

    get :create_from_hub, params: { source_page_id: 6403 }
    assert_response :not_found
  end

  test 'analytics only includes visible usage' do
    login_as('hub_reader_a')
    as_json!

    get :analytics, params: { id: 6403 }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body.fetch('total_uses')
    assert_equal({ 'Agreements' => 1 }, body.fetch('usage_by_project'))
  end

  test 'copy requires edit permission and admin can preview template' do
    login_as('hub_reader_a')
    as_json!

    post :copy, params: { id: 6403, project_id: 'procurement-kb' }
    assert_response :forbidden

    login_as('hub_admin')
    as_json!

    post :preview, params: { id: 6403, variables: { 'name' => 'Admin' } }
    assert_response :success
    assert JSON.parse(response.body).key?('preview')
  end

  test 'use hides inaccessible target projects and create_from_hub requires edit permission' do
    login_as('hub_reader_a')

    post :use, params: { id: 6403, project_id: 'process-docs', title: 'Supplier Draft' }
    assert_response :not_found

    post :create_from_hub, params: { source_page_id: 6401, title: '[Template] Master Playbook Copy' }
    assert_response :forbidden
  end

  test 'use endpoint creates page from template with variable substitution' do
    login_as('hub_admin')

    # Template content with variables
    template_page = WikiPage.find(6403)
    template_page.content.update!(text: 'Hello {{ name }}, welcome to {{ project }}.')

    assert_difference('WikiPage.count', 1) do
      assert_difference('WikiHub::PageLink.count', 1) do
        post :use, params: { id: 6403, project_id: 'agreements', title: 'Welcome Draft', variables: { 'name' => 'Alice', 'project' => 'TestProject' } }
      end
    end

    assert_response :redirect
    new_page = WikiPage.find_by!(title: 'Welcome Draft')
    assert_includes new_page.content.text, 'Hello Alice, welcome to TestProject.'

    # Verify template usage link was created
    link = WikiHub::PageLink.find_by!(source_page_id: new_page.id, target_page_id: 6403)
    assert_equal 'template_usage', link.link_type
  end

  test 'create_from_hub endpoint creates template from source page' do
    login_as('hub_admin')
    WikiHub::Indexer.stubs(:reindex_page)

    assert_difference('WikiPage.count', 1) do
      assert_difference('WikiHub::PageProfile.count', 1) do
        post :create_from_hub, params: { source_page_id: 6401, project_id: 'agreements', title: '[Template] Master Playbook', category: 'playbooks', summary: 'Master template summary' }
      end
    end

    assert_response :redirect
    new_template = WikiPage.find_by!(title: '[Template] Master Playbook')
    profile = WikiHub::PageProfile.find_by!(wiki_page_id: new_template.id)
    assert_equal 'template', profile.page_kind
    assert_equal 'playbooks', profile.category
    assert_equal 'Master template summary', profile.summary
  end

  test 'create_from_hub html renders supported category options for authenticated admin' do
    login_as('hub_admin')

    get :create_from_hub, params: { source_page_id: 6401 }

    assert_response :success
    assert_select '[data-testid="wiki-hub-create-template-form"]', 1
    assert_select 'select[data-testid="wiki-hub-create-template-category"] option[value="legal"]', text: 'Legal'
    assert_select 'select[data-testid="wiki-hub-create-template-category"] option[value="operations"]', text: 'Operations'
  end

  test 'use action rescues RecordInvalid and renders form with errors' do
    login_as('hub_admin')

    # Force a validation failure inside the transaction by stubbing PageLink.create!
    WikiHub::PageLink.stubs(:create!).raises(ActiveRecord::RecordInvalid.new(WikiHub::PageLink.new))

    post :use, params: { id: 6403, project_id: 'agreements', title: 'Draft Page', variables: {} }

    # Should render the form again with error message (rescue path)
    assert_response :success
    assert_includes response.body, 'error'
  end

  test 'create_from_hub rescues RecordInvalid and renders form with errors' do
    login_as('hub_admin')
    WikiHub::Indexer.stubs(:reindex_page)

    # Force validation failure by stubbing PageProfile update!
    profile_stub = WikiHub::PageProfile.new
    profile_stub.stubs(:update!).raises(ActiveRecord::RecordInvalid.new(profile_stub))
    WikiHub::PageProfile.stubs(:find_or_initialize_by).returns(profile_stub)

    post :create_from_hub, params: { source_page_id: 6401, project_id: 'agreements', title: '[Template] Test', category: 'test' }

    # Should render the form again with error message (rescue path)
    assert_response :success
    assert_includes response.body, 'error'
  end

  test 'templates index json includes serialized templates and html uses preloaded template stats' do
    login_as('hub_admin')
    as_json!

    get :index
    assert_response :success

    body = JSON.parse(response.body)
    template = body.fetch('templates').find { |entry| entry.fetch('title') == 'Contract Boilerplate' }
    assert_equal 'legal', template.fetch('category')

    @request.accept = 'text/html'
    @request.content_type = 'text/html'
    get :index
    assert_response :success
    assert_includes response.body, 'Contract Boilerplate'
  end

  test 'copy keeps template profile metadata and tracks template copy link' do
    login_as('hub_admin')
    as_json!

    WikiHub::Indexer.stubs(:reindex_page)

    assert_difference('WikiPage.count', 1) do
      assert_difference('WikiHub::PageProfile.count', 1) do
        assert_difference('WikiHub::PageLink.count', 1) do
          post :copy, params: { id: 6403, project_id: 'agreements' }
        end
      end
    end

    assert_response :success
    copied_page = WikiPage.order(:id).last
    copied_profile = WikiHub::PageProfile.find_by!(wiki_page_id: copied_page.id)
    copy_link = WikiHub::PageLink.find_by!(source_page_id: copied_page.id, target_page_id: 6403, link_type: 'template_copy')

    assert_equal 'template', copied_profile.page_kind
    assert_equal 'legal', copied_profile.category
    assert_equal copied_page.project.id, Project.find_by!(identifier: 'agreements').id
    assert_equal 6403, copy_link.target_page_id
  end

  private

  def create_snapshot(wiki_page_id, project_id, title)
    WikiHub::PageSnapshot.create!(wiki_page_id: wiki_page_id, project_id: project_id, title: title, searchable_text: title)
  end

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
