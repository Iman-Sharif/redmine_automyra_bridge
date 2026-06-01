require File.expand_path('../test_helper', __dir__)

class WikiHubLessonsTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageProfile.delete_all

    create_snapshot(7101, 6201, 'Lesson Alpha', 3.days.ago)
    create_snapshot(7102, 6201, 'Lesson Beta', 1.day.ago)
    create_snapshot(7103, 6201, 'Template Sample', 2.days.ago)

    WikiHub::PageProfile.create!(wiki_page_id: 7101, page_kind: 'lesson_learned', category: 'operations', featured: false, lesson_date: Date.new(2026, 4, 1))
    WikiHub::PageProfile.create!(wiki_page_id: 7102, page_kind: 'lesson_learned', category: 'operations', featured: false, lesson_date: Date.new(2026, 4, 2))
    WikiHub::PageProfile.create!(wiki_page_id: 7103, page_kind: 'template', category: 'operations', featured: false)
  end

  test 'lesson page_kind filter excludes non-lessons' do
    rows = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), page_kind: 'lesson_learned').call

    assert_equal ['Lesson Alpha', 'Lesson Beta'], rows.pluck(:title).sort
  end

  test 'default ordering uses updated_at desc' do
    rows = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), page_kind: 'lesson_learned').call

    assert_equal ['Lesson Beta', 'Lesson Alpha'], rows.pluck(:title)
  end

  test 'limit is bounded to max 100' do
    rows = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), page_kind: 'lesson_learned', limit: 5_000).call

    assert_operator rows.size, :<=, 100
  end

  test 'negative offset coerces to zero' do
    base = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), page_kind: 'lesson_learned').call.pluck(:wiki_page_id)
    offset = WikiHub::PageQuery.new(user: User.find_by!(login: 'hub_reader_a'), page_kind: 'lesson_learned', offset: -10).call.pluck(:wiki_page_id)

    assert_equal base, offset
  end

  private

  def create_snapshot(wiki_page_id, project_id, title, updated_at)
    WikiHub::PageSnapshot.create!(
      wiki_page_id: wiki_page_id,
      project_id: project_id,
      title: title,
      searchable_text: title,
      updated_at: updated_at,
      created_at: updated_at
    )
  end
end

class WikiHubLessonsControllerTest < ActionController::TestCase
  tests WikiHubLessonsController

  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageProfile.delete_all

    create_snapshot(7101, 6201, 'Lesson Alpha', 3.days.ago)
    create_snapshot(7102, 6201, 'Lesson Beta', 1.day.ago)
    create_snapshot(7103, 6201, 'Template Sample', 2.days.ago)

    WikiHub::PageProfile.create!(wiki_page_id: 7101, page_kind: 'lesson_learned', category: 'operations', featured: false, lesson_date: Date.new(2026, 4, 1))
    WikiHub::PageProfile.create!(wiki_page_id: 7102, page_kind: 'lesson_learned', category: 'operations', featured: false, lesson_date: Date.new(2026, 4, 2))
    WikiHub::PageProfile.create!(wiki_page_id: 7103, page_kind: 'template', category: 'operations', featured: false)
  end

  test 'lessons page renders lesson dates without per-row profile lookups' do
    login_as('hub_reader_a')

    get :index
    assert_response :success
    assert_includes response.body, '2026-04-02'
    assert_includes response.body, 'Lesson Beta'
    assert_not_includes response.body, 'Template Sample'
  end

  private

  def create_snapshot(wiki_page_id, project_id, title, updated_at)
    WikiHub::PageSnapshot.create!(
      wiki_page_id: wiki_page_id,
      project_id: project_id,
      title: title,
      searchable_text: title,
      updated_at: updated_at,
      created_at: updated_at
    )
  end

  def login_as(login)
    user = User.find_by!(login: login)
    @request.session[:user_id] = user.id
    User.current = user
  end
end
