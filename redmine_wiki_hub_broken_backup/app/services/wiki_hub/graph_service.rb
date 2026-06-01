require 'set'

module WikiHub
  class GraphService
    MAX_NODES = 150
    MAX_EDGES = 300

    def initialize(user)
      @user = user || User.anonymous
    end

    def call(root_page_id: nil, max_nodes: MAX_NODES, max_edges: MAX_EDGES)
      return { nodes: [], edges: [] } if root_page_id.blank?

      visible_pages = WikiHub::PageUniverseService.new(user).visible_pages
      root_id = root_page_id.to_i
      return { nodes: [], edges: [] } unless visible_pages.where(wiki_page_id: root_id).exists?

      visible_page_ids_subquery = visible_pages.select(:wiki_page_id)
      
      outbound_edges = WikiHub::PageLink
                       .where(source_page_id: root_id, resolved: true)
                       .where(target_page_id: visible_page_ids_subquery)
                       .limit(max_edges.to_i / 2)

      inbound_edges = WikiHub::PageLink
                      .where(target_page_id: root_id, resolved: true)
                      .where(source_page_id: visible_page_ids_subquery)
                      .limit(max_edges.to_i / 2)

      raw_edges = (outbound_edges + inbound_edges).first([max_edges.to_i, MAX_EDGES].min)

      connected_ids = raw_edges.map { |e| [e.source_page_id, e.target_page_id] }.flatten.uniq
      node_ids = ([root_id] + connected_ids).uniq.first([max_nodes.to_i, MAX_NODES].min)
      
      allowed_node_ids = node_ids.to_set
      limited_edges = raw_edges.select { |edge| allowed_node_ids.include?(edge.source_page_id) && allowed_node_ids.include?(edge.target_page_id) }
      
      node_data = visible_pages
        .where(wiki_page_id: node_ids)
        .joins('LEFT JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
        .pluck(:wiki_page_id, :title, 'wiki_hub_page_profiles.page_kind')

      titles_and_kinds_by_id = node_data.to_h do |row|
        id, title, kind = row
        [id, { title: title, page_kind: kind || 'standard' }]
      end

      {
        nodes: node_ids.map { |id| { id: id, title: titles_and_kinds_by_id.dig(id, :title) || "Page #{id}", page_kind: titles_and_kinds_by_id.dig(id, :page_kind) || 'standard' } },
        edges: limited_edges.map { |edge| { from: edge.source_page_id, to: edge.target_page_id } }
      }
    end

    private

    attr_reader :user
  end
end
