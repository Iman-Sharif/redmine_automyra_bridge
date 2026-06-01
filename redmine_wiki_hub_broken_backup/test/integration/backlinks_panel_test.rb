require File.expand_path('../integration_test_helper', __dir__)

class BacklinksPanelTest < RedmineWikiHub::IntegrationTest
  setup do
    WikiHub::PageLink.delete_all
    WikiHub::PageSnapshot.delete_all
  end

  test 'reindexing page creates backlinks edges for wiki links' do
    page = WikiPage.find(6401)
    page.content.text = 'See [[Lessons 2026-04]] and [[@procurement-kb/Contract Boilerplate]]'
    page.content.save!

    WikiHub::Indexer.reindex_page(page)

    assert_equal 2, WikiHub::PageLink.where(source_page_id: 6401).count
  end

  test 'remove_page clears source links and marks target references unresolved' do
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')

    WikiHub::Indexer.remove_page(6403)

    link = WikiHub::PageLink.find_by!(source_page_id: 6401)
    assert_nil link.target_page_id
    assert_not link.resolved
  end

  test 'rebuild reconciles unresolved link once target exists' do
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: nil, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: false, link_type: 'wiki')

    WikiHub::Indexer.send(:reconcile_unresolved_links!)

    link = WikiHub::PageLink.find_by!(source_page_id: 6401, target_title: 'Contract Boilerplate')
    assert link.resolved
    assert_equal 6403, link.target_page_id
  end

  test 'cross-project wiki syntax is parsed into expected target fields' do
    parsed = WikiHub::LinkParser.parse('[[@procurement-kb/Contract Boilerplate]]', source_project_id: 6201)

    assert_equal 1, parsed.size
    assert_equal 6202, parsed.first.fetch(:target_project_id)
    assert_equal 'Contract Boilerplate', parsed.first.fetch(:target_title)
  end
end
