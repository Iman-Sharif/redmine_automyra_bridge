require File.expand_path('../test_helper', __dir__)

class BacklinksServiceTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageLink.delete_all
    WikiHub::PageSnapshot.delete_all

    create_snapshot(6401, 6201, 'Master Playbook')
    create_snapshot(6402, 6203, 'Supplier Onboarding')
    create_snapshot(6403, 6202, 'Contract Boilerplate')

    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6402, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: nil, target_project_id: 6201, target_title: 'Missing', resolved: false, link_type: 'wiki')
  end

  test 'returns resolved backlinks for target page' do
    rows = backlinks_for(User.find_by!(login: 'hub_admin'), 6403)

    assert_equal 2, rows.size
  end

  test 'filters backlinks by source page visibility' do
    rows = backlinks_for(User.find_by!(login: 'hub_reader_a'), 6403)

    assert_equal [6401], rows.map(&:source_page_id)
  end

  test 'user with no wiki visibility sees no backlinks' do
    rows = backlinks_for(User.find_by!(login: 'hub_no_wiki'), 6403)

    assert_equal [], rows
  end

  test 'unresolved links are excluded from backlinks list' do
    rows = backlinks_for(User.find_by!(login: 'hub_admin'), 6401)

    assert_equal [], rows
  end

  test 'backlinks are sorted by source page id for deterministic output' do
    rows = backlinks_for(User.find_by!(login: 'hub_admin'), 6403)

    assert_equal rows.map(&:source_page_id).sort, rows.map(&:source_page_id)
  end

  private

  def create_snapshot(wiki_page_id, project_id, title)
    WikiHub::PageSnapshot.create!(wiki_page_id: wiki_page_id, project_id: project_id, title: title, searchable_text: title)
  end

  def backlinks_for(user, target_page_id)
    visible_ids = WikiHub::PageUniverseService.new(user).visible_pages.pluck(:wiki_page_id)
    WikiHub::PageLink.where(target_page_id: target_page_id, resolved: true, source_page_id: visible_ids).order(:source_page_id).to_a
  end
end
