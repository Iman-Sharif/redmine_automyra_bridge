require File.expand_path('../test_helper', __dir__)

class PageSnapshotTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageSnapshot.where(wiki_page_id: [6401, 6402]).delete_all
  end

  test 'valid snapshot persists' do
    snapshot = WikiHub::PageSnapshot.new(
      wiki_page_id: 6401,
      project_id: 6201,
      title: 'Master Playbook',
      searchable_text: 'playbook searchable body',
      current_version_id: nil
    )

    assert snapshot.valid?
  end

  test 'wiki_page_id must be unique' do
    WikiHub::PageSnapshot.create!(
      wiki_page_id: 6402,
      project_id: 6202,
      title: 'Supplier Onboarding',
      searchable_text: 'supplier onboarding'
    )

    duplicate = WikiHub::PageSnapshot.new(
      wiki_page_id: 6402,
      project_id: 6202,
      title: 'Supplier Onboarding Duplicate',
      searchable_text: 'duplicate'
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:wiki_page_id], 'has already been taken'
  end
end
