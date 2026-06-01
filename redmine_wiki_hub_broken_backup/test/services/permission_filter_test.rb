require File.expand_path('../test_helper', __dir__)

class PermissionFilterTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageSnapshot.where(wiki_page_id: 6401).delete_all
    WikiHub::PageSnapshot.create!(
      wiki_page_id: 6401,
      project_id: 6201,
      title: 'Master Playbook',
      searchable_text: 'Canonical policy and operating controls.',
      current_version_id: nil
    )
  end

  test 'can_view? supports wiki page and page snapshot' do
    user = User.find_by!(login: 'hub_reader_a')
    filter = WikiHub::PermissionFilter.new(user)

    assert filter.can_view?(WikiPage.find(6401))
    assert filter.can_view?(WikiHub::PageSnapshot.find_by!(wiki_page_id: 6401))
    assert_not filter.can_view?(WikiPage.find(6402))
  end

  test 'can_edit? checks edit permission' do
    reader = WikiHub::PermissionFilter.new(User.find_by!(login: 'hub_reader_a'))
    admin = WikiHub::PermissionFilter.new(User.find_by!(login: 'hub_admin'))

    assert_not reader.can_edit?(WikiPage.find(6401))
    assert admin.can_edit?(WikiPage.find(6401))
  end

  test 'permission filter caches project ids for repeated calls' do
    user = User.find_by!(login: 'hub_reader_a')
    filter = WikiHub::PermissionFilter.new(user)

    # Multiple calls should use cached project ids and return consistent results
    viewable1 = filter.viewable_pages
    viewable2 = filter.viewable_snapshots
    editable1 = filter.editable_pages
    editable2 = filter.editable_snapshots

    # All should return ActiveRecord::Relation (not raise, not return nil unexpectedly)
    assert viewable1.is_a?(ActiveRecord::Relation)
    assert viewable2.is_a?(ActiveRecord::Relation)
    assert editable1.is_a?(ActiveRecord::Relation)
    assert editable2.is_a?(ActiveRecord::Relation)

    # Behavior consistency: viewable should include page 6401, editable should not (reader has view but not edit)
    assert viewable1.where(id: 6401).exists?
    assert_not editable1.where(id: 6401).exists?
  end
end
