require File.expand_path('../test_helper', __dir__)

class WikiHubMetadataTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageProfile.where(wiki_page_id: [6401, 6402]).delete_all
    WikiHub::Tagging.where(wiki_page_id: [6401]).delete_all
  end

  test 'page metadata fields persist for valid profile' do
    profile = WikiHub::PageProfile.create!(
      wiki_page_id: 6401,
      page_kind: 'standard',
      category: 'policy',
      summary: 'Canonical policy page',
      featured: true,
      lesson_date: nil
    )

    assert profile.persisted?
    assert_equal 'policy', profile.category
    assert profile.featured
  end

  test 'invalid page kind is rejected' do
    assert_raises(ArgumentError) do
      WikiHub::PageProfile.new(wiki_page_id: 6401, page_kind: 'invalid', featured: false)
    end
  end

  test 'tagging uniqueness prevents duplicate metadata tags' do
    tag = WikiHub::Tag.create!(name: 'policy')
    WikiHub::Tagging.create!(wiki_page_id: 6401, tag_id: tag.id)

    duplicate = WikiHub::Tagging.new(wiki_page_id: 6401, tag_id: tag.id)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:wiki_page_id], 'has already been taken'
  end

  test 'featured must be boolean' do
    profile = WikiHub::PageProfile.new(wiki_page_id: 6402, page_kind: 'template', featured: nil)

    assert_not profile.valid?
    assert_includes profile.errors[:featured], 'is not included in the list'
  end
end

class WikiHubMetadataControllerTest < ActionController::TestCase
  tests WikiHubMetadataController

  def setup
    WikiHub::PageProfile.where(wiki_page_id: [6401, 6402, 6403]).delete_all
    WikiHub::Tagging.where(wiki_page_id: [6401, 6402, 6403]).delete_all
    WikiHub::Tag.where(name: %w[policy metadata]).delete_all
  end

  test 'show hides inaccessible pages and allows visible pages' do
    login_as('hub_reader_a')

    get :show, params: { project_id: 'process-docs', id: 'Supplier Onboarding' }
    assert_response :not_found
  end

  test 'update returns forbidden for read only access and succeeds for admin' do
    login_as('hub_reader_a')
    as_json!

    patch :update, params: { project_id: 'agreements', id: 'Master Playbook', category: 'policy' }
    assert_response :forbidden

    login_as('hub_admin')
    as_json!

    patch :update, params: { project_id: 'agreements', id: 'Master Playbook', category: 'policy', page_kind: 'lesson_learned', summary: 'Updated', featured: '1', tags: 'metadata', lesson_date: '2026-04-15' }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 'policy', body.fetch('category')
    assert_equal ['metadata'], body.fetch('tags')
    assert_equal '2026-04-15', body.fetch('lesson_date')

    profile = WikiHub::PageProfile.find_by!(wiki_page_id: 6401)
    assert_equal Date.new(2026, 4, 15), profile.lesson_date
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
