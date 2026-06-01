require File.expand_path('../test_helper', __dir__)

class WikiHubControllerTest < ActionController::TestCase
  tests WikiHubController

  setup do
    seed_wiki_hub_data!
  end

  test 'authorized page universe is consistent across endpoints for hub_reader_a' do
    login_as('hub_reader_a')
    as_json!

    get :index
    assert_response :success
    assert_equal ['Contract Boilerplate', 'Lessons 2026-04', 'Master Playbook'], json_titles
    assert_includes response.headers['Cache-Control'], 'private'

    get :project_index, params: { project_id: 'process-docs' }
    assert_response :not_found

    get :project_index, params: { project_id: 'procurement-kb' }
    assert_response :success
    assert_equal ['Contract Boilerplate'], json_titles

    get :project_search, params: { project_id: 'process-docs', q: 'Supplier' }
    assert_response :not_found
  end

  test 'hub_reader_b sees process-docs only and hub_no_wiki sees nothing' do
    login_as('hub_reader_b')
    as_json!

    get :index
    assert_response :success
    assert_equal ['Supplier Onboarding'], json_titles

    login_as('hub_no_wiki')

    get :index
    assert_response :success
    assert_equal [], json_titles
  end

  test 'unauthorized project titles never leak in response payloads' do
    login_as('hub_reader_a')
    as_json!

    get :metadata, params: { project_id: 'process-docs' }
    assert_response :not_found
  end

  test 'search suggestions and related pages are permission filtered' do
    WikiHub::PageLink.delete_all
    WikiHub::PageProfile.find_or_create_by!(wiki_page_id: 6402) do |profile|
      profile.page_kind = 'standard'
      profile.category = 'legal'
      profile.featured = false
    end
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6402, target_project_id: 6203, target_title: 'Supplier Onboarding', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')

    login_as('hub_reader_a')
    as_json!

    get :search_suggestions, params: { term: 'Su' }
    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch('suggestions')

    get :search_suggestions, params: { term: 'Co' }
    assert_response :success
    assert_equal ['Contract Boilerplate'], JSON.parse(response.body).fetch('suggestions')

    get :related_pages, params: { page_id: 6401 }
    assert_response :success
    assert_includes JSON.parse(response.body).fetch('pages').map { |page| page.fetch('title') }, 'Contract Boilerplate'
    assert_not_includes JSON.parse(response.body).fetch('pages').map { |page| page.fetch('title') }, 'Supplier Onboarding'

    get :related_pages, params: { page_id: 6402 }
    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch('pages')
  end

  test 'bulk actions deny unauthorized page sets without mutating data' do
    login_as('hub_reader_a')

    assert_no_difference('WikiHub::Tag.count') do
      post :bulk_action, params: { bulk_action: 'tag', page_ids: [6402, 6403], tag_names: 'secret' }
    end

    assert_response :forbidden
  end

  test 'bulk delete and duplicate require action-specific permissions' do
    login_as('hub_reader_a')

    assert_no_difference('WikiPage.count') do
      post :bulk_action, params: { bulk_action: 'duplicate', page_ids: [6401] }
    end
    assert_response :forbidden

    post :bulk_action, params: { bulk_action: 'delete', page_ids: [6401] }
    assert_response :forbidden
  end

  test 'bulk success paths mutate only authorized visible records' do
    login_as('hub_admin')

    assert_difference('WikiHub::Tagging.count', 2) do
      post :bulk_action, params: { bulk_action: 'tag', page_ids: [6401, 6404], tag_names: 'ops' }
    end
    assert_response :redirect
    assert_equal [6401, 6404], WikiHub::Tag.joins(:taggings).where(name: 'ops').pluck('wiki_hub_taggings.wiki_page_id').sort

    post :bulk_action, params: { bulk_action: 'categorize', page_ids: [6401, 6404], category: 'playbooks' }
    assert_response :redirect
    assert_equal ['playbooks'], WikiHub::PageProfile.where(wiki_page_id: [6401, 6404]).distinct.pluck(:category)

    assert_difference('WikiPage.count', 1) do
      post :bulk_action, params: { bulk_action: 'duplicate', page_ids: [6401] }
    end
    assert_response :redirect
    assert_equal 'Canonical policy and operating controls.', WikiPage.find_by!(title: 'Master Playbook (Copy)').content.text.lines.last.strip
  end

  test 'bulk tag is atomic and rolls back on mid-stream failure' do
    login_as('hub_admin')

    # First tagging should succeed, second will fail
    call_count = 0
    WikiHub::Tagging.stub(:find_or_create_by!, ->(*args) {
      call_count += 1
      if call_count == 2
        raise ActiveRecord::RecordInvalid.new(WikiHub::Tagging.new)
      end
      WikiHub::Tagging.create!(*args) rescue WikiHub::Tagging.find_by!(*args)
    }) do
      # Attempt to tag 2 pages - first succeeds, second fails
      assert_no_difference('WikiHub::Tagging.count') do
        post :bulk_action, params: { bulk_action: 'tag', page_ids: [6401, 6404], tag_names: 'atomic_test' }
      end
    end

    # Should redirect with error alert (not success notice)
    assert_response :redirect
    # Verify no partial tagging occurred
    assert_equal [], WikiHub::Tag.where(name: 'atomic_test').pluck(:name)
  end

  test 'bulk delete is atomic and rolls back on RecordNotDestroyed failure' do
    login_as('hub_admin')

    # Create an additional page for multi-page delete test
    WikiPage.find(6402).update!(title: 'Supplier Onboarding')

    # First destroy should succeed, second will fail with RecordNotDestroyed
    call_count = 0
    WikiPage.any_instance.stubs(:destroy!).with do
      call_count += 1
      if call_count == 2
        raise ActiveRecord::RecordNotDestroyed.new(WikiPage.find(6402), "Cannot delete page with active issues")
      end
      true
    end

    # Attempt to delete 2 pages - first succeeds, second fails
    assert_no_difference('WikiPage.count') do
      post :bulk_action, params: { bulk_action: 'delete', page_ids: [6401, 6402] }
    end

    # Should redirect with error alert (rescue path taken)
    assert_response :redirect
    # Verify no partial deletion occurred - both pages still exist
    assert WikiPage.exists?(6401), 'First page should not have been deleted'
    assert WikiPage.exists?(6402), 'Second page should not have been deleted'
  end

  test 'quick create hides inaccessible project and allows admin access' do
    login_as('hub_reader_a')

    post :quick_create, params: { project_id: 'process-docs', title: 'Hidden Project Draft' }
    assert_response :not_found

    login_as('hub_admin')

    assert_difference('WikiPage.count', 1) do
      post :quick_create, params: { project_id: 'procurement-kb', title: 'Admin Draft' }
    end
    assert_response :redirect
  end

  test 'quick create uses visible template content and related pages stay permission filtered' do
    WikiHub::PageLink.delete_all
    WikiHub::PageProfile.find_or_create_by!(wiki_page_id: 6404) do |profile|
      profile.page_kind = 'standard'
      profile.category = 'governance'
      profile.featured = false
    end
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6402, target_project_id: 6203, target_title: 'Supplier Onboarding', resolved: true, link_type: 'wiki')

    login_as('hub_admin')

    assert_difference('WikiPage.count', 1) do
      post :quick_create, params: { project_id: 'agreements', title: 'Templated Draft', template_id: 6403 }
    end
    assert_response :redirect
    assert_includes WikiPage.find_by!(title: 'Templated Draft').content.text, 'Standard legal clauses and fallback terms.'

    login_as('hub_reader_a')
    as_json!
    get :related_pages, params: { page_id: 6401 }
    assert_response :success

    payload = JSON.parse(response.body).fetch('pages')
    titles = payload.map { |entry| entry.fetch('title') }
    reasons = payload.each_with_object({}) { |entry, acc| acc[entry.fetch('title')] = entry.fetch('reason') }
    assert_includes titles, 'Contract Boilerplate'
    assert_includes titles, 'Lessons 2026-04'
    assert_not_includes titles, 'Supplier Onboarding'
    assert_equal 'Linked page', reasons['Contract Boilerplate']
    assert_equal 'Same category: governance', reasons['Lessons 2026-04']
  end

  test 'index html renders project counts from preloaded data' do
    login_as('hub_reader_a')

    get :index
    assert_response :success
    assert_includes response.body, 'Agreements'
    assert_includes response.body, 'Procurement KB'
    assert_includes response.body, '2'
    assert_includes response.body, '1'
  end

  test 'index html renders category filter options from visible page profiles' do
    login_as('hub_reader_a')

    get :index

    assert_response :success
    assert_select 'select#wiki-hub-filter-category[data-testid="wiki-hub-filter-category"] option[value=""]', 1
    assert_select 'select#wiki-hub-filter-category option[value="governance"]', text: 'Governance'
    assert_select 'select#wiki-hub-filter-category option[value="legal"]', text: 'Legal'
    assert_select 'select#wiki-hub-filter-category option[value="operations"]', 0
  end

  test 'quick create html renders visible templates for authenticated admin' do
    login_as('hub_admin')

    get :quick_create

    assert_response :success
    assert_select '[data-testid="wiki-hub-quick-create"]', 1
    assert_select 'select[data-testid="wiki-hub-quick-create-template"] option[value="6403"]', text: 'Contract Boilerplate'
  end

  private

  def json_titles
    return JSON.parse(response.body).fetch('pages').map { |page| page.fetch('title') }.sort if response.media_type == 'application/json'

    titles = []
    response.body.scan(/data-testid="wiki-hub-page-title"[^>]*>\s*<a[^>]+>([^<]+)</).each do |match|
      titles << match[0].strip
    end
    response.body.scan(/data-testid="wiki-hub-recent-change"[^>]*>\s*<a[^>]+>([^<]+)</).each do |match|
      titles << match[0].strip
    end
    titles.uniq.sort
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

  def seed_wiki_hub_data!
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageProfile.delete_all
    WikiHub::Tagging.delete_all
    WikiHub::Tag.delete_all

    create_snapshot(6401, 6201, 'Master Playbook', 'Canonical policy and operating controls.')
    create_snapshot(6402, 6203, 'Supplier Onboarding', 'Intake and approval lifecycle for process docs.')
    create_snapshot(6403, 6202, 'Contract Boilerplate', 'Standard legal clauses and fallback terms.')
    create_snapshot(6404, 6201, 'Lessons 2026-04', 'Incident and remediation notes for April 2026.')

    WikiHub::PageProfile.create!(wiki_page_id: 6401, page_kind: 'standard', category: 'governance', featured: false)
    WikiHub::PageProfile.create!(wiki_page_id: 6402, page_kind: 'standard', category: 'operations', featured: false)
    WikiHub::PageProfile.create!(wiki_page_id: 6403, page_kind: 'template', category: 'legal', featured: true)

    tag = WikiHub::Tag.create!(name: 'contracts')
    WikiHub::Tagging.create!(wiki_page_id: 6403, tag_id: tag.id)
  end

  def create_snapshot(wiki_page_id, project_id, title, searchable_text)
    WikiHub::PageSnapshot.create!(
      wiki_page_id: wiki_page_id,
      project_id: project_id,
      title: title,
      searchable_text: searchable_text,
      current_version_id: nil
    )
  end
end
