module WikiHub
  class PageQuery
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    ALLOWED_ORDER_COLUMNS = {
      'updated_at' => 'wiki_hub_page_snapshots.updated_at',
      'title' => 'wiki_hub_page_snapshots.title'
    }.freeze

    def initialize(user:, project_id: nil, category: nil, page_kind: nil, tag: nil, limit: DEFAULT_LIMIT, offset: 0,
                   order: 'updated_at', direction: 'desc')
      @user = user
      @project_id = project_id
      @category = category
      @page_kind = page_kind
      @tag = tag
      @limit = limit
      @offset = offset
      @order = order
      @direction = direction
    end

    def call
      apply_ordering(apply_filters(base_scope)).limit(safe_limit).offset(safe_offset)
    end

    def relation
      apply_filters(base_scope)
    end

    private

    attr_reader :user, :project_id, :category, :page_kind, :tag, :limit, :offset, :order, :direction

    def base_scope
      WikiHub::PageUniverseService.new(user).visible_pages.includes(:project)
    end

    def apply_filters(scope)
      filtered = scope
      filtered = filtered.where(project_id: resolved_project_id) if project_id.present?

      if category.present? || page_kind.present?
        filtered = filtered.joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
        filtered = filtered.where('wiki_hub_page_profiles.category = ?', category) if category.present?
        filtered = filtered.where('wiki_hub_page_profiles.page_kind = ?', page_kind) if page_kind.present?
      end

      if tag.present?
        filtered = filtered.joins('INNER JOIN wiki_hub_taggings ON wiki_hub_taggings.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
                           .joins('INNER JOIN wiki_hub_tags ON wiki_hub_tags.id = wiki_hub_taggings.tag_id')
                           .where('LOWER(wiki_hub_tags.name) = ?', tag.to_s.downcase)
                           .distinct
      end

      filtered
    end

    def resolved_project_id
      return project_id.to_i if project_id.to_s.match?(/\A\d+\z/)

      Project.where(identifier: project_id.to_s).pick(:id)
    end

    def apply_ordering(scope)
      order_column = ALLOWED_ORDER_COLUMNS.fetch(order.to_s, ALLOWED_ORDER_COLUMNS['updated_at'])
      order_direction = direction.to_s.casecmp('asc').zero? ? 'ASC' : 'DESC'
      scope.order(Arel.sql("#{order_column} #{order_direction}"))
    end

    def safe_limit
      requested = limit.to_i
      return DEFAULT_LIMIT if requested <= 0

      [requested, MAX_LIMIT].min
    end

    def safe_offset
      [offset.to_i, 0].max
    end
  end
end
