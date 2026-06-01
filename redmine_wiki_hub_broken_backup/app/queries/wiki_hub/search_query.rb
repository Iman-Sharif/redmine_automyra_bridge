module WikiHub
  class SearchQuery
    MAX_LIMIT = 50

    def initialize(user:, term:, project_id: nil, category: nil, page_kind: nil, tag: nil, 
                   author: nil, date_from: nil, date_to: nil, sort_by: 'relevance', limit: MAX_LIMIT)
      @term = term.to_s.strip
      @limit = limit
      @sort_by = sort_by
      @filters = {
        project_id: project_id,
        category: category,
        page_kind: page_kind,
        tag: tag,
        author: author,
        date_from: date_from,
        date_to: date_to
      }
      @page_query = WikiHub::PageQuery.new(
        user: user,
        project_id: project_id,
        category: category,
        page_kind: page_kind,
        tag: tag,
        limit: MAX_LIMIT,
        offset: 0,
        order: 'updated_at',
        direction: 'desc'
      )
    end

    def call
      scope = page_query.relation.distinct(false)
      
      # Apply text search if term provided
      if term.present?
        escaped_term = ActiveRecord::Base.sanitize_sql_like(term)
        prefix_match = "#{escaped_term}%"
        contains_match = "%#{escaped_term}%"
        
        scope = scope.where(
          'wiki_hub_page_snapshots.title ILIKE :contains OR wiki_hub_page_snapshots.searchable_text ILIKE :contains OR similarity(wiki_hub_page_snapshots.title, :term) > 0.1',
          contains: contains_match,
          term: term
        )
        
        scope = scope.reorder(Arel.sql(sanitized_ranking_sql(prefix_match, contains_match)))
      else
        scope = scope.reorder(updated_at: :desc)
      end
      
      # Apply additional filters
      scope = apply_author_filter(scope)
      scope = apply_date_filter(scope)
      
      scope.limit(safe_limit)
    end
    
    # Phase 3: Faceted search results
    def facets
      base_scope = page_query.relation.distinct(false)
      
      if term.present?
        escaped_term = ActiveRecord::Base.sanitize_sql_like(term)
        base_scope = base_scope.where(
          'wiki_hub_page_snapshots.title ILIKE :pattern OR wiki_hub_page_snapshots.searchable_text ILIKE :pattern',
          pattern: "%#{escaped_term}%"
        )
      end
      
      {
        categories: category_facets(base_scope),
        page_kinds: page_kind_facets(base_scope),
        projects: project_facets(base_scope),
        tags: tag_facets(base_scope),
        authors: author_facets(base_scope)
      }
    end

    private

    attr_reader :term, :limit, :page_query

    def sanitized_ranking_sql(prefix_match, contains_match)
      ActiveRecord::Base.send(
        :sanitize_sql_array,
        [
          <<~SQL.squish,
        CASE
          WHEN LOWER(wiki_hub_page_snapshots.title) = LOWER(?) THEN 0
          WHEN wiki_hub_page_snapshots.title ILIKE ? THEN 1
          WHEN wiki_hub_page_snapshots.searchable_text ILIKE ? THEN 2
          ELSE 3
        END ASC,
        similarity(wiki_hub_page_snapshots.title, ?) DESC,
        wiki_hub_page_snapshots.updated_at DESC,
        wiki_hub_page_snapshots.title ASC
      SQL
          term,
          prefix_match,
          contains_match,
          term
        ]
      )
    end

    def safe_limit
      requested = limit.to_i
      return MAX_LIMIT if requested <= 0

      [requested, MAX_LIMIT].min
    end

    # Phase 3: Filter methods
    def apply_author_filter(scope)
      return scope unless @filters[:author].present?
      
      scope.joins(:wiki_page)
           .joins('INNER JOIN wiki_contents ON wiki_contents.page_id = wiki_pages.id')
           .where(wiki_contents: { author_id: @filters[:author] })
    end
    
    def apply_date_filter(scope)
      scope = scope.where('wiki_hub_page_snapshots.updated_at >= ?', @filters[:date_from]) if @filters[:date_from].present?
      scope = scope.where('wiki_hub_page_snapshots.updated_at <= ?', @filters[:date_to]) if @filters[:date_to].present?
      scope
    end
    
    # Phase 3: Facet calculation methods
    def category_facets(base_scope)
      base_scope.joins(:wiki_page)
                .joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_pages.id')
                .group('wiki_hub_page_profiles.category')
                .count
                .transform_keys { |k| k || 'uncategorized' }
    end
    
    def page_kind_facets(base_scope)
      base_scope.joins(:wiki_page)
                .joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_pages.id')
                .group('wiki_hub_page_profiles.page_kind')
                .count
                .transform_keys { |k| k || 'standard' }
    end
    
    def project_facets(base_scope)
      base_scope.joins(:project)
                .group('projects.name')
                .count
    end
    
    def tag_facets(base_scope)
      base_scope.joins(:wiki_page)
                .joins('INNER JOIN wiki_hub_taggings ON wiki_hub_taggings.wiki_page_id = wiki_pages.id')
                .joins('INNER JOIN wiki_hub_tags ON wiki_hub_tags.id = wiki_hub_taggings.tag_id')
                .group('wiki_hub_tags.name')
                .count
    end
    
    def author_facets(base_scope)
      base_scope.joins(:wiki_page)
                .joins('INNER JOIN wiki_contents ON wiki_contents.page_id = wiki_pages.id')
                .joins('INNER JOIN users ON users.id = wiki_contents.author_id')
                .group('users.firstname, users.lastname')
                .count
                .transform_keys { |k| k.join(' ') }
    end
  end
end
