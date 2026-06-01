require File.expand_path('../test_helper', __dir__)

class PageProfileTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageProfile.where(wiki_page_id: [6401, 6404]).delete_all
  end

  test 'valid page profile persists' do
    profile = WikiHub::PageProfile.new(
      wiki_page_id: 6404,
      page_kind: 'lesson_learned',
      category: 'operations',
      lesson_date: Date.new(2026, 4, 1),
      summary: 'Lessons learned summary',
      featured: true
    )

    assert profile.valid?
  end

  test 'wiki_page_id must be unique' do
    WikiHub::PageProfile.create!(
      wiki_page_id: 6401,
      page_kind: 'standard',
      category: 'governance',
      summary: 'Base profile',
      featured: false
    )

    duplicate = WikiHub::PageProfile.new(
      wiki_page_id: 6401,
      page_kind: 'template',
      category: 'governance',
      summary: 'Duplicate profile',
      featured: false
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:wiki_page_id], 'has already been taken'
  end

  test 'lesson_learned requires lesson_date' do
    # Invalid: lesson_learned without lesson_date
    invalid_profile = WikiHub::PageProfile.new(
      wiki_page_id: 6405,
      page_kind: 'lesson_learned',
      category: 'operations',
      lesson_date: nil,
      featured: false
    )

    assert_not invalid_profile.valid?
    assert_includes invalid_profile.errors[:lesson_date], "can't be blank"

    # Valid: lesson_learned with lesson_date
    valid_profile = WikiHub::PageProfile.new(
      wiki_page_id: 6406,
      page_kind: 'lesson_learned',
      category: 'operations',
      lesson_date: Date.new(2026, 4, 15),
      featured: false
    )

    assert valid_profile.valid?
  end

  test 'standard and template do not require lesson_date' do
    standard_profile = WikiHub::PageProfile.new(
      wiki_page_id: 6407,
      page_kind: 'standard',
      category: 'governance',
      lesson_date: nil,
      featured: false
    )

    assert standard_profile.valid?

    template_profile = WikiHub::PageProfile.new(
      wiki_page_id: 6408,
      page_kind: 'template',
      category: 'legal',
      lesson_date: nil,
      featured: true
    )

    assert template_profile.valid?
  end
end
