class WikiHubController < ApplicationController
  before_action :require_login
  before_action :force_html_format, only: [:index, :search, :project_index, :project_search, :quick_create]
  before_action :set_cache_headers, only: [:index, :search, :templates, :lessons]
  before_action :resolve_scoped_project!, only: [:project_index, :project_search, :metadata]

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def index
    # Eager load projects with their associations needed by the view
    visible_page_ids = WikiHub::PageUniverseService.new(User.current).visible_pages.distinct.pluck(:project_id)
    @projects = Project.where(id: visible_page_ids).order(:name)
    project_ids = @projects.map(&:id)
    
    @pages = page_query.call
    @category_options = visible_category_options
    
    # Global recent pages (for main content area)
    visible_pages_scope = WikiHub::PageUniverseService.new(User.current).visible_pages.includes(:project)
    @recent_pages = visible_pages_scope.order(updated_at: :desc).limit(10)
    
    # Project counts - single query for all counts
    project_pages = visible_pages_scope.where(project_id: project_ids)
    @project_page_counts = project_pages.group(:project_id).count
    @project_recent_counts = project_pages.where('wiki_hub_page_snapshots.updated_at > ?', 7.days.ago).group(:project_id).count
    
    # Efficient recent pages per project - only fetch what's needed (first 3 per project)
    @project_recent_pages = fetch_limited_recent_pages_per_project(project_ids, visible_pages_scope, 3)

    respond_to do |format|
      format.html { render :index }
      format.json { render json: { pages: serialize_pages(@pages) } }
    end
  end

  def bulk_action
    action = params[:bulk_action]
    page_ids = Array(params[:page_ids])

    if page_ids.empty?
      redirect_to knowledge_hub_path, alert: l(:wiki_hub_no_pages_selected)
      return
    end

    pages = permission_filter.viewable_pages(WikiPage.where(id: page_ids)).includes(:wiki).to_a
    if pages.size != page_ids.map(&:to_i).uniq.size
      render_403
      return
    end

    authorized_pages = authorized_bulk_pages(action, pages)
    if authorized_pages.nil?
      render_403
      return
    end

    begin
      WikiPage.transaction do
        case action
        when 'delete'
          deleted_count = authorized_pages.count { |page| page.destroy! }
          redirect_to knowledge_hub_path, notice: l(:wiki_hub_bulk_deleted, count: deleted_count) and return

        when 'tag'
          tag_names = params[:tag_names].to_s.split(',').map(&:strip).reject(&:blank?)
          authorized_pages.each { |page| apply_tags!(page, tag_names) }
          redirect_to knowledge_hub_path, notice: l(:wiki_hub_bulk_tagged, count: authorized_pages.count) and return

        when 'categorize'
          category = params[:category]
          authorized_pages.each { |page| categorize_page!(page, category) }
          redirect_to knowledge_hub_path, notice: l(:wiki_hub_bulk_categorized, count: authorized_pages.count) and return

        when 'duplicate'
          authorized_pages.each { |page| duplicate_page!(page) }
          redirect_to knowledge_hub_path, notice: l(:wiki_hub_bulk_duplicated, count: authorized_pages.count) and return

        else
          redirect_to knowledge_hub_path, alert: l(:wiki_hub_unknown_action) and return
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to knowledge_hub_path, alert: l(:wiki_hub_bulk_action_failed, message: e.record.errors.full_messages.join(', '))
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to knowledge_hub_path, alert: l(:wiki_hub_bulk_action_failed, message: "Could not delete page: #{e.message}")
    end
  end

  def quick_create
    @projects = editable_projects
    @available_templates = permission_filter.viewable_pages(
      WikiPage
        .joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_pages.id')
        .where(wiki_hub_page_profiles: { page_kind: 'template' })
    ).order(:title)

    if request.post?
      project = resolve_target_project!(quick_create_params[:project_id])
      return unless project

      wiki = project.wiki || project.create_wiki(start_page: 'Wiki')
      content_text = default_content_or_template

      @page = WikiPage.new(wiki: wiki, title: quick_create_params[:title])
      @content = WikiContent.new(
        page: @page,
        author: User.current,
        text: content_text,
        comments: 'Created from Wiki Hub'
      )
      @page.content = @content

      if @page.save
        WikiHub::Indexer.reindex_page(@page)

        redirect_to edit_project_wiki_page_path(project_id: project.identifier, id: @page.title),
                    notice: l(:wiki_hub_page_created)
      else
        flash.now[:error] = @page.errors.full_messages.join(', ')
        render :quick_create_form
      end
    else
      render :quick_create_form
    end
  end

  def search_suggestions
    term = params[:term].to_s.strip

    if term.blank? || term.length < 2
      render json: { suggestions: [] }
      return
    end

    suggestions = permission_filter
      .viewable_snapshots(
        WikiHub::PageSnapshot
          .joins(:project)
          .where('wiki_hub_page_snapshots.title ILIKE ?', "#{term}%")
          .where(projects: { status: Project::STATUS_ACTIVE })
      )
      .distinct
      .limit(10)
      .pluck(:title)

    render json: {
      suggestions: suggestions,
      recent_searches: []
    }
  end

  def related_pages
    page = permission_filter.viewable_pages(WikiPage.where(id: params[:page_id])).first

    if page.nil?
      render json: { pages: [] }
      return
    end

    related = find_related_pages(page)

    render json: {
      pages: related.map do |related_page|
        {
          id: related_page.wiki_page_id,
          title: related_page.title,
          project_name: related_page.project&.name,
          reason: related_page.reason
        }
      end
    }
  end

  def search
    @search_query = WikiHub::SearchQuery.new(
      user: User.current,
      term: params[:q],
      project_id: params[:project_id],
      category: params[:category],
      page_kind: params[:page_kind],
      tag: params[:tag],
      author: params[:author],
      date_from: params[:date_from],
      date_to: params[:date_to],
      sort_by: params[:sort_by] || 'relevance',
      limit: params[:limit]
    )

    # Eager load associations needed by the view to avoid N+1 queries
    @pages = @search_query.call.includes(:project, :wiki_page_profile)
    @facets = @search_query.facets if params[:q].present?
    @search_term = params[:q]

    # Preload author name for active filters display (avoid view query)
    @author_name = User.find_by(id: params[:author])&.name if params[:author].present?

    respond_to do |format|
      format.html { render :search }
      format.json { render json: {
        pages: serialize_pages(@pages),
        facets: @facets,
        total: @pages.count
      } }
    end
  end

  def project_index
    @pages = page_query.call
    respond_to do |format|
      format.html { render :index }
      format.json { render json: { pages: serialize_pages(@pages) } }
    end
  end

  def project_search
    @pages = search_query.call
    respond_to do |format|
      format.html { render :search }
      format.json { render json: { pages: serialize_pages(@pages) } }
    end
  end

  def metadata
    payload = {
      project_id: @scoped_project.id,
      status: 'ok',
      visible_count: page_query.call.count
    }

    respond_to do |format|
      format.html { render json: payload }
      format.json { render json: payload }
    end
  end

  private

  def set_cache_headers
    response.headers['Cache-Control'] = 'private, max-age=300'
    response.headers['Expires'] = 5.minutes.from_now.httpdate
  end

  def force_html_format
    unless params[:format] == 'json' || request.headers['Accept'].to_s.include?('application/json')
      request.format = :html
    end
  end

  def page_query
    @page_query ||= WikiHub::PageQuery.new(
      user: User.current,
      project_id: scoped_project_id,
      category: params[:category],
      page_kind: params[:page_kind],
      tag: params[:tag],
      limit: params[:limit],
      offset: params[:offset],
      order: params[:order],
      direction: params[:direction]
    )
  end

  def search_query
    @search_query ||= WikiHub::SearchQuery.new(
      user: User.current,
      term: params[:q],
      project_id: scoped_project_id,
      category: params[:category],
      page_kind: params[:page_kind],
      tag: params[:tag]
    )
  end

  def scoped_project_id
    @scoped_project&.id || params[:project_id]
  end

  def resolve_scoped_project!
    @scoped_project = permission_filter.find_viewable_project(params[:project_id])
    render_404 unless @scoped_project
  end

  def visible_projects
    Project.where(id: WikiHub::PageUniverseService.new(User.current).visible_pages.distinct.pluck(:project_id))
  end

  def visible_category_options
    WikiHub::PageUniverseService.new(User.current)
      .visible_pages
      .joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
      .where.not(wiki_hub_page_profiles: { category: [nil, ''] })
      .distinct
      .order('wiki_hub_page_profiles.category ASC')
      .pluck('wiki_hub_page_profiles.category')
  end

  def editable_projects
    permission_filter.editable_projects(visible_projects).sort_by(&:name)
  end

  def serialize_pages(scope)
    scope.map do |page|
      {
        wiki_page_id: page.wiki_page_id,
        project_id: page.project_id,
        title: page.title,
        updated_at: page.updated_at
      }
    end
  end

  def fetch_limited_recent_pages_per_project(project_ids, visible_pages_scope, limit_per_project)
    return {} if project_ids.blank?

    visible_pages_scope
      .where(project_id: project_ids)
      .order(updated_at: :desc)
      .to_a
      .group_by(&:project_id)
      .transform_values { |pages| pages.first(limit_per_project) }
  end

  def render_not_found
    render json: { error: 'Not found' }, status: :not_found
  end

  def find_related_pages(page)
    related = []
    visible_snapshots = permission_filter.viewable_snapshots.includes(:project)

      if (page_profile = WikiHub::PageProfile.find_by(wiki_page_id: page.id))
      same_category = visible_snapshots
        .joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
        .where(wiki_hub_page_profiles: { category: page_profile.category })
        .where.not(wiki_page_id: page.id)
        .limit(5)
        .map do |snapshot|
          OpenStruct.new(
            wiki_page_id: snapshot.wiki_page_id,
            title: snapshot.title,
            project: snapshot.project,
            reason: "Same category: #{page_profile.category}"
          )
        end
      related.concat(same_category)
    end

    title_words = page.title.split.reject { |word| word.length < 4 }
    if title_words.any?
      similar_title = visible_snapshots
        .where('wiki_hub_page_snapshots.title ILIKE ANY (ARRAY[?])', title_words.map { |word| "%#{word}%" })
        .where.not(wiki_page_id: page.id)
        .limit(3)
        .map do |snapshot|
          OpenStruct.new(
            wiki_page_id: snapshot.wiki_page_id,
            title: snapshot.title,
            project: snapshot.project,
            reason: 'Similar title'
          )
        end
      related.concat(similar_title)
    end

    linked_pages = visible_snapshots
      .where(
        wiki_page_id: WikiHub::PageLink
          .where(source_page_id: page.id)
          .limit(5)
          .select(:target_page_id)
      )
      .includes(:project)
      .map do |target|
        OpenStruct.new(
          wiki_page_id: target.wiki_page_id,
          title: target.title,
          project: target.project,
          reason: 'Linked page'
        )
      end
    related.concat(linked_pages)

    same_project = visible_snapshots
      .where(project_id: page.wiki&.project_id)
      .where.not(wiki_page_id: page.id)
      .order(updated_at: :desc)
      .limit(3)
      .map do |snapshot|
        OpenStruct.new(
          wiki_page_id: snapshot.wiki_page_id,
          title: snapshot.title,
          project: snapshot.project,
          reason: 'Same project'
        )
      end
    related.concat(same_project)

    related.uniq { |related_page| related_page.wiki_page_id }.first(8)
  end

  def default_content_or_template
    if quick_create_params[:template_id].present?
      template = permission_filter.viewable_pages(WikiPage.where(id: quick_create_params[:template_id])).first
      raise ActiveRecord::RecordNotFound unless template

      template.content&.text.to_s
    else
      "h1. #{quick_create_params[:title]}\n\np. Enter your content here..."
    end
  end

  def quick_create_params
    params.permit(:project_id, :template_id, :title)
  end

  def apply_tags!(page, tag_names)
    tag_names.each do |tag_name|
      tag = WikiHub::Tag.find_or_create_by!(name: tag_name.downcase)
      WikiHub::Tagging.find_or_create_by!(wiki_page_id: page.id, tag_id: tag.id)
    end
  end

  def categorize_page!(page, category)
    profile = WikiHub::PageProfile.find_or_initialize_by(wiki_page_id: page.id)
    profile.update!(category: category)
  end

  def duplicate_page!(page)
    new_page = WikiPage.new(
      wiki: page.wiki,
      title: "#{page.title} (Copy)"
    )
    new_page.content = WikiContent.new(
      page: new_page,
      text: page.content&.text.to_s,
      author: User.current
    )
    new_page.save!
    WikiHub::Indexer.reindex_page(new_page)
  end

  def authorized_bulk_pages(action, pages)
    authorized = case action
                 when 'delete'
                   pages.select { |page| permission_filter.can_delete?(page) }
                 when 'tag', 'categorize', 'duplicate'
                   pages.select { |page| permission_filter.can_edit?(page) }
                 else
                   return nil
                 end

    return nil if authorized.size != pages.size

    authorized
  end

  def resolve_target_project!(project_id)
    project = if project_id.to_s.match?(/\A\d+\z/)
                Project.find_by(id: project_id.to_i)
              else
                Project.find_by(identifier: project_id)
              end

    unless project && permission_filter.can_view?(project)
      render_404
      return nil
    end

    unless permission_filter.can_edit?(project)
      render_403
      return nil
    end

    project
  end

  def permission_filter
    @permission_filter ||= WikiHub::PermissionFilter.new(User.current)
  end
end
