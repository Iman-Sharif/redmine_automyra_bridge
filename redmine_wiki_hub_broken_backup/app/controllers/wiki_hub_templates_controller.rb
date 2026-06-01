class WikiHubTemplatesController < ApplicationController
  before_action :require_login
  before_action :find_source_page, only: [:create_from_hub]
  before_action :find_template, only: [:show, :analytics, :use, :preview, :copy]

  def index
    visible_pages = WikiHub::PageUniverseService.new(User.current).visible_pages
    @templates = visible_pages
                 .joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
                 .where(wiki_hub_page_profiles: { page_kind: 'template' })
                 .order('wiki_hub_page_snapshots.updated_at DESC')
    @template_profiles = WikiHub::PageProfile.where(wiki_page_id: @templates.map(&:wiki_page_id)).index_by(&:wiki_page_id)
    @template_usage_counts = WikiHub::PageLink.where(target_page_id: @templates.map(&:wiki_page_id)).group(:target_page_id).count

    @template_stats = calculate_template_stats(@templates)

    respond_to do |format|
      format.html { render :index }
      format.json { render json: {
        templates: serialize_templates(@templates),
        stats: @template_stats
      } }
    end
  end

  def show
    unless @template
      render_404
      return
    end

    @profile = WikiHub::PageProfile.find_by(wiki_page_id: @template.id)
    unless template_page?(@profile)
      render_404
      return
    end

    @usage_count = visible_template_uses(@template).count
    @copies_created = join_page_profiles(visible_template_copies(@template))
      .where(wiki_hub_page_profiles: { page_kind: 'standard' })
      .count

    @related_templates = find_related_templates(@template)
  end

  def analytics
    unless @template
      render_404
      return
    end

    unless template_page?
      render_404
      return
    end

    @usage_data = {
      total_uses: visible_template_uses(@template).count,
      copies_created: visible_template_copies(@template).count,
      last_used: visible_template_uses(@template).maximum(:created_at),
      usage_by_project: usage_by_project(@template),
      usage_over_time: usage_over_time(@template, 30.days.ago)
    }

    respond_to do |format|
      format.html { render :analytics }
      format.json { render json: @usage_data }
    end
  end

  def create_from_hub
    @projects = editable_projects
    @category_options = visible_category_options
    if params[:source_page_id].present? && @source_page.nil?
      render_404
      return
    end

    if request.post?
      unless @source_page
        render_404
        return
      end

      target_project = params[:project_id].present? ? resolve_target_project!(params[:project_id]) : @source_page.project
      return unless target_project

      unless permission_filter.can_edit?(target_project)
        render_403
        return
      end

      begin
        WikiPage.transaction do
          @template_page = copy_page_as_template(@source_page, target_project, template_creation_params)
          profile = WikiHub::PageProfile.find_or_initialize_by(wiki_page_id: @template_page.id)
          profile.update!(
            page_kind: 'template',
            category: template_creation_params[:category] || 'General',
            summary: template_creation_params[:summary]
          )

          WikiHub::Indexer.reindex_page(@template_page)
        end

        redirect_to knowledge_hub_templates_path,
                    notice: l(:wiki_hub_template_created)
      rescue ActiveRecord::RecordInvalid => e
        flash.now[:error] = e.record.errors.full_messages.join(', ')
        render :create_from_hub_form
      end
    else
      render :create_from_hub_form
    end
  end

  def use
    unless @template
      render_404
      return
    end

    @profile = WikiHub::PageProfile.find_by(wiki_page_id: @template.id)
    unless template_page?(@profile)
      render_404
      return
    end

    @projects = editable_projects
    template_content = @template.content&.text.to_s
    @variables = WikiHub::TemplateVariableService.extract_variables(template_content)

    if request.post?
      target_project = resolve_target_project!(template_use_params[:project_id])
      return unless target_project

      variable_values = template_variable_values
      processed_content = WikiHub::TemplateVariableService.process_template(template_content, variable_values)

      wiki = target_project.wiki || Wiki.create!(project: target_project, start_page: 'Wiki')
      title = unique_title_for(wiki, template_use_params[:title].presence || @template.title.to_s.gsub(/\[Template\]/i, '').strip)

      @new_page = WikiPage.new(wiki: wiki, title: title)
      @new_page.content = WikiContent.new(
        page: @new_page,
        text: processed_content,
        author: User.current,
        comments: "Created from template: #{@template.title}"
      )

      begin
        WikiPage.transaction do
          @new_page.save!
          WikiHub::PageLink.create!(
            source_page_id: @new_page.id,
            target_page_id: @template.id,
            link_type: 'template_usage'
          )

          WikiHub::Indexer.reindex_page(@new_page)
        end

        redirect_to edit_project_wiki_page_path(project_id: target_project.identifier, id: @new_page.title),
                    notice: l(:wiki_hub_page_created_from_template)
      rescue ActiveRecord::RecordInvalid => e
        flash.now[:error] = e.record.errors.full_messages.join(', ')
        render :use_form
      end
    else
      render :use_form
    end
  end

  def preview
    unless @template
      render_404
      return
    end

    unless template_page?
      render_404
      return
    end

    template_content = @template.content&.text.to_s
    variable_values = template_variable_values

    @preview_content = WikiHub::TemplateVariableService.process_template(template_content, variable_values)
    @variables_used = WikiHub::TemplateVariableService.extract_variables(template_content)

    render json: {
      preview: @preview_content,
      variables: @variables_used.map { |variable| variable[:name] }
    }
  end

  def copy
    template_page = @template
    unless template_page
      render_404
      return
    end

    unless WikiHub::PageProfile.find_by(wiki_page_id: template_page.id)&.page_kind == 'template'
      render_404
      return
    end

    target_project = resolve_target_project!(params[:project_id])
    return unless target_project

    copied_page = nil
    WikiPage.transaction do
      copied_page = copy_template_to_project(template_page, target_project)
      copy_template_profile!(template_page, copied_page)
      WikiHub::PageLink.find_or_create_by!(
        source_page_id: copied_page.id,
        target_page_id: template_page.id,
        link_type: 'template_copy'
      )
    end

    render json: {
      status: 'ok',
      wiki_page_id: copied_page.id,
      project_id: target_project.id,
      title: copied_page.title
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { status: 'error', errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def find_template
    @template = permission_filter.viewable_pages(WikiPage.where(id: params[:id])).first
  end

  def find_source_page
    return unless params[:source_page_id].present?

    @source_page = permission_filter.viewable_pages(WikiPage.where(id: params[:source_page_id])).first
  end

  def calculate_template_stats(templates)
    return {} if templates.blank?

    template_ids = templates.map(&:wiki_page_id)
    visible_page_ids = permission_filter.viewable_snapshots.pluck(:wiki_page_id)

    {
      total_templates: templates.count,
      total_usage: WikiHub::PageLink.where(target_page_id: template_ids, source_page_id: visible_page_ids).count,
      most_used_template_id: most_used_template(template_ids),
      templates_by_category: join_page_profiles(templates).group('wiki_hub_page_profiles.category').count,
      recently_created: templates.where('wiki_hub_page_snapshots.created_at > ?', 7.days.ago).count
    }
  end

  def most_used_template(template_ids)
    return nil if template_ids.blank?

    visible_page_ids = permission_filter.viewable_snapshots.pluck(:wiki_page_id)

    WikiHub::PageLink
      .where(target_page_id: template_ids, source_page_id: visible_page_ids)
      .group(:target_page_id)
      .count
      .max_by { |_, count| count }
      &.first
  end

  def usage_by_project(template)
    WikiHub::PageLink
      .joins('INNER JOIN wiki_pages ON wiki_pages.id = wiki_hub_page_links.source_page_id')
      .joins('INNER JOIN wikis ON wikis.id = wiki_pages.wiki_id')
      .joins('INNER JOIN projects ON projects.id = wikis.project_id')
      .where(target_page_id: template.id, source_page_id: permission_filter.viewable_snapshots.select(:wiki_page_id))
      .group('projects.name')
      .count
  end

  def usage_over_time(template, since_date)
    WikiHub::PageLink
      .where(target_page_id: template.id, source_page_id: permission_filter.viewable_snapshots.select(:wiki_page_id))
      .where('wiki_hub_page_links.created_at >= ?', since_date)
      .group("DATE_TRUNC('day', wiki_hub_page_links.created_at)")
      .count
  end

  def find_related_templates(template)
    return [] unless template

    template_profile = WikiHub::PageProfile.find_by(wiki_page_id: template.id)
    return [] unless template_profile

    join_page_profiles(permission_filter.viewable_snapshots)
      .where(wiki_hub_page_profiles: { page_kind: 'template', category: template_profile.category })
      .where.not(wiki_page_id: template.id)
      .limit(4)
  end

  def serialize_templates(templates)
    profiles_by_page_id = @template_profiles || WikiHub::PageProfile.where(wiki_page_id: templates.map(&:wiki_page_id)).index_by(&:wiki_page_id)

    templates.map do |template|
      profile = profiles_by_page_id[template.wiki_page_id]
      {
        id: template.wiki_page_id,
        title: template.title,
        category: profile&.category,
        summary: profile&.summary,
        updated_at: template.updated_at
      }
    end
  end

  def copy_page_as_template(source_page, target_project, params)
    wiki = target_project.wiki || Wiki.create!(project: target_project, start_page: 'Wiki')

    base_title = params[:title].presence || "[Template] #{source_page.title}"
    title = unique_title_for(wiki, base_title)

    page = WikiPage.new(wiki: wiki, title: title)
    page.content = WikiContent.new(
      page: page,
      text: source_page.content&.text.to_s,
      author: User.current,
      comments: "Created as template from #{source_page.title}"
    )
    page.save!
    page
  end

  def visible_projects
    Project.where(id: WikiHub::PageUniverseService.new(User.current).visible_pages.distinct.pluck(:project_id))
  end

  def editable_projects
    permission_filter.editable_projects(visible_projects).sort_by(&:name)
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

  def permission_filter
    @permission_filter ||= WikiHub::PermissionFilter.new(User.current)
  end

  def find_project_from_param(value)
    return Project.find_by(id: value.to_i) if value.to_s.match?(/\A\d+\z/)

    Project.find_by(identifier: value)
  end

  def resolve_target_project!(value)
    project = find_project_from_param(value)

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

  def template_page?(profile = WikiHub::PageProfile.find_by(wiki_page_id: @template&.id))
    profile&.page_kind == 'template'
  end

  def visible_template_uses(template)
    WikiHub::PageLink.where(target_page_id: template.id, source_page_id: permission_filter.viewable_snapshots.select(:wiki_page_id))
  end

  def visible_template_copies(template)
    permission_filter.viewable_snapshots.where('wiki_hub_page_snapshots.title ILIKE ?', "%#{template.title}%")
  end

  def join_page_profiles(scope)
    scope.joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
  end

  def copy_template_to_project(template_page, project)
    wiki = project.wiki || Wiki.create!(project: project, start_page: template_page.title.to_s)
    title = unique_title_for(wiki, template_page.title.to_s)

    page = WikiPage.new(wiki: wiki, title: title)
    page.content = WikiContent.new(page: page, text: template_page.content&.text.to_s, author: User.current)
    page.save!
    WikiHub::Indexer.reindex_page(page)
    page
  end

  def copy_template_profile!(template_page, copied_page)
    source_profile = WikiHub::PageProfile.find_by(wiki_page_id: template_page.id)
    return unless source_profile

    WikiHub::PageProfile.create!(
      wiki_page_id: copied_page.id,
      page_kind: source_profile.page_kind,
      category: source_profile.category,
      summary: source_profile.summary,
      featured: false,
      lesson_date: source_profile.lesson_date
    )
  end

  def unique_title_for(wiki, base_title)
    candidate = base_title
    suffix = 0
    while wiki.pages.where('LOWER(title) = ?', candidate.downcase).exists?
      suffix += 1
      candidate = "#{base_title} (Copy #{suffix})"
    end

    candidate
  end

  def template_creation_params
    params.permit(:project_id, :source_page_id, :title, :category, :summary)
  end

  def template_use_params
    params.permit(:project_id, :title)
  end

  def template_variable_values
    values = params[:variables]
    return {} unless values.respond_to?(:to_unsafe_h) || values.is_a?(Hash)

    values.to_h.transform_keys(&:to_s)
  end
end
