class WikiHubBacklinksController < ApplicationController
  before_action :require_login
  before_action :set_cache_headers, only: [:index]

  def index
    @target_page = resolve_target_page
    @backlinks = backlinks_for(@target_page&.id)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          target_page_id: @target_page&.id,
          target_title: @target_page&.title,
          backlinks: @backlinks.map do |row|
            {
              source_page_id: row.source_page_id,
              source_project_id: row.project_id,
              source_title: row.title
            }
          end
        }
      end
    end
  end

  private

  def resolve_target_page
    return permission_filter.viewable_pages(WikiPage.where(id: params[:page_id].to_i)).first if params[:page_id].present?

    return nil if params[:id].blank?

    project = permission_filter.find_viewable_project(params[:project_id])
    return nil unless project

    if params[:id].to_s.match?(/\A\d+\z/)
      WikiPage.joins(:wiki).find_by(id: params[:id], wikis: { project_id: project.id })
    else
      WikiPage.joins(:wiki)
              .where(wikis: { project_id: project.id })
              .where('LOWER(wiki_pages.title) = ?', params[:id].to_s.downcase)
              .first
    end
  end

  def backlinks_for(target_page_id)
    return [] if target_page_id.blank?

    visible_source_ids = WikiHub::PageUniverseService.new(User.current).visible_pages.select(:wiki_page_id)

    WikiHub::PageLink.where(target_page_id: target_page_id, resolved: true, source_page_id: visible_source_ids)
                     .joins('INNER JOIN wiki_hub_page_snapshots ON wiki_hub_page_snapshots.wiki_page_id = wiki_hub_page_links.source_page_id')
                     .select('wiki_hub_page_links.source_page_id, wiki_hub_page_snapshots.project_id, wiki_hub_page_snapshots.title')
                     .order('wiki_hub_page_snapshots.title ASC')
  end

  def permission_filter
    @permission_filter ||= WikiHub::PermissionFilter.new(User.current)
  end

  def set_cache_headers
    response.headers['Cache-Control'] = 'private, max-age=300'
    response.headers['Expires'] = 5.minutes.from_now.httpdate
  end
end
