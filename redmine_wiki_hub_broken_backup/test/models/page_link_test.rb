require File.expand_path('../test_helper', __dir__)

class PageLinkTest < RedmineWikiHub::TestCase
  test 'valid resolved link with target page' do
    link = WikiHub::PageLink.new(
      source_page_id: 6401,
      target_page_id: 6403,
      target_project_id: 6202,
      target_title: 'Contract Boilerplate',
      resolved: true,
      link_type: 'wiki'
    )

    assert link.valid?
  end

  test 'allows unresolved link without target page id' do
    link = WikiHub::PageLink.new(
      source_page_id: 6404,
      target_page_id: nil,
      target_project_id: 6203,
      target_title: 'Unknown Playbook',
      resolved: false,
      link_type: 'wiki'
    )

    assert link.valid?
  end
end
