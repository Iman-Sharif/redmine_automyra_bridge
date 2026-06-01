require File.expand_path('../test_helper', __dir__)

class GraphServiceTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageLink.delete_all

    create_snapshot(6401, 6201, 'Master Playbook')
    create_snapshot(6403, 6202, 'Contract Boilerplate')
    create_snapshot(6404, 6201, 'Lessons 2026-04')
    create_snapshot(6402, 6203, 'Supplier Onboarding')

    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6404, target_project_id: 6201, target_title: 'Lessons 2026-04', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6402, target_project_id: 6203, target_title: 'Supplier Onboarding', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6404, target_page_id: nil, target_project_id: 6201, target_title: 'Missing', resolved: false, link_type: 'wiki')
  end

  test 'graph requires a root page id' do
    graph = graph_for(User.find_by!(login: 'hub_admin'), nil)

    assert_equal [], graph[:nodes]
    assert_equal [], graph[:edges]
  end

  test 'graph excludes unresolved links' do
    graph = graph_for(User.find_by!(login: 'hub_admin'), 6404)

    assert_equal [], graph[:edges]
  end

  test 'graph filters unauthorized neighbor nodes' do
    graph = graph_for(User.find_by!(login: 'hub_reader_a'), 6401)

    assert_not_includes graph[:nodes], 6402
    assert_not_includes graph[:edges].map { |e| e[:to] }, 6402
  end

  test 'graph keeps authorized neighbors for reader a' do
    graph = graph_for(User.find_by!(login: 'hub_reader_a'), 6401)

    assert_equal [6401, 6403, 6404], graph[:nodes].sort
  end

  test 'graph enforces node and edge caps' do
    user = User.find_by!(login: 'hub_admin')
    210.times do |idx|
      target_id = 8_000 + idx
      create_snapshot(target_id, 6201, "Node #{idx}")
      WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: target_id, target_project_id: 6201, target_title: "Node #{idx}", resolved: true, link_type: 'wiki')
    end

    graph = graph_for(user, 6401)
    assert_operator graph[:nodes].size, :<=, 150
    assert_operator graph[:edges].size, :<=, 300
  end

  private

  def create_snapshot(wiki_page_id, project_id, title)
    WikiHub::PageSnapshot.create!(wiki_page_id: wiki_page_id, project_id: project_id, title: title, searchable_text: title)
  end

  def graph_for(user, root_page_id, max_nodes: 150, max_edges: 300)
    return { nodes: [], edges: [] } if root_page_id.blank?

    visible_page_ids = WikiHub::PageUniverseService.new(user).visible_pages.pluck(:wiki_page_id)
    return { nodes: [], edges: [] } unless visible_page_ids.include?(root_page_id)

    edges = WikiHub::PageLink.where(source_page_id: root_page_id, resolved: true, target_page_id: visible_page_ids).limit(max_edges)
    nodes = ([root_page_id] + edges.pluck(:target_page_id)).uniq.first(max_nodes)

    { nodes: nodes, edges: edges.map { |edge| { from: edge.source_page_id, to: edge.target_page_id } } }
  end
end
