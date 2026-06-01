require File.expand_path('../test_helper', __dir__)

class WikiHubSearchTest < ActionController::TestCase
  tests WikiHubController

  setup do
    seed_data!
  end

  test 'search returns empty pages for blank query' do
    login_as('hub_reader_a')

    get :search, params: { q: '   ' }

    assert_response :success
    assert_equal [], json_titles
  end

  test 'search matches visible title for authorized user' do
    login_as('hub_reader_a')

    get :search, params: { q: 'Master' }

    assert_response :success
    assert_equal ['Master Playbook'], json_titles
  end

  test 'search does not leak unauthorized project pages' do
    login_as('hub_reader_a')

    get :search, params: { q: 'Supplier' }

    assert_response :success
    assert_equal [], json_titles
  end

  test 'search respects project identifier filter' do
    login_as('hub_reader_a')

    get :project_search, params: { project_id: 'procurement-kb', q: 'Contract' }

    assert_response :success
    assert_equal ['Contract Boilerplate'], json_titles
  end

  test 'search result count is capped at 10' do
    login_as('hub_admin')
    12.times do |idx|
      create_snapshot(9000 + idx, 6201, "Master #{idx}", "Master body #{idx}")
    end

    get :search, params: { q: 'Master', limit: 999 }

    assert_response :success
    assert_operator json_titles.size, :<=, 10
  end

  private

  def json_titles
    titles = []
    response.body.scan(/data-testid="wiki-hub-search-result-title"[^>]*>\s*<a[^>]+>([^<]+)</).each do |match|
      titles << match[0].strip
    end
    titles.uniq.sort
  end

  def login_as(login)
    user = User.find_by!(login: login)
    @request.session[:user_id] = user.id
    User.current = user
  end

  def seed_data!
    WikiHub::PageSnapshot.delete_all

    create_snapshot(6401, 6201, 'Master Playbook', 'Canonical policy and operating controls.')
    create_snapshot(6402, 6203, 'Supplier Onboarding', 'Intake and approval lifecycle for process docs.')
    create_snapshot(6403, 6202, 'Contract Boilerplate', 'Standard legal clauses and fallback terms.')
    create_snapshot(6404, 6201, 'Lessons 2026-04', 'Incident and remediation notes for April 2026.')
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
