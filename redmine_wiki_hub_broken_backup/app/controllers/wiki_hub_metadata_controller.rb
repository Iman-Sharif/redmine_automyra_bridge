class WikiHubMetadataController < ApplicationController
  before_action :require_login
  before_action :find_project
  before_action :find_wiki_page

  def show
    unless permission_filter.can_view?(@wiki_page)
      render_404
      return
    end

    @profile = WikiHub::PageProfile.find_or_initialize_by(wiki_page_id: @wiki_page.id)
    @tag_names = WikiHub::Tag.joins(:taggings).where(wiki_hub_taggings: { wiki_page_id: @wiki_page.id }).order(:name).pluck(:name)
  end

  def update
    unless permission_filter.can_view?(@wiki_page)
      render_404
      return
    end

    unless permission_filter.can_edit?(@wiki_page)
      render_403
      return
    end

    profile = nil
    WikiPage.transaction do
      profile = WikiHub::PageProfile.find_or_initialize_by(wiki_page_id: @wiki_page.id)
      profile.assign_attributes(metadata_params)
      profile.featured = false if profile.featured.nil?
      profile.save!

      replace_tags!(@wiki_page.id, tags_param)
      WikiHub::Indexer.reindex_page(@wiki_page)
    end

    render json: {
      status: 'ok',
      wiki_page_id: @wiki_page.id,
      page_kind: profile.page_kind,
      category: profile.category,
      tags: tag_names_for(@wiki_page.id),
      lesson_date: profile.lesson_date&.to_s
    }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { status: 'error', errors: [e.message] }, status: :unprocessable_entity
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    @project = Project.find_by(identifier: params[:project_id])
    render_404 unless @project
  end

  def find_wiki_page
    @wiki_page = if params[:id].to_s.match?(/\A\d+\z/)
                   WikiPage.joins(:wiki).find_by(id: params[:id], wikis: { project_id: @project.id })
                 else
                   WikiPage.joins(:wiki)
                           .where(wikis: { project_id: @project.id })
                           .where('LOWER(wiki_pages.title) = ?', params[:id].to_s.downcase)
                           .first
                 end

    render_404 unless @wiki_page
  end

  def metadata_params
    permitted = params.permit(:category, :page_kind, :summary, :featured, :tags, :lesson_date)

    {
      category: permitted[:category],
      page_kind: permitted[:page_kind].presence || 'standard',
      summary: permitted[:summary],
      featured: ActiveModel::Type::Boolean.new.cast(permitted[:featured]),
      lesson_date: parse_lesson_date(permitted[:lesson_date])
    }
  end

  def parse_lesson_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end

  def tags_param
    params.permit(:tags)[:tags].to_s.split(',').map(&:strip).reject(&:blank?).uniq
  end

  def replace_tags!(wiki_page_id, names)
    WikiHub::Tagging.where(wiki_page_id: wiki_page_id).delete_all

    names.each do |name|
      tag = WikiHub::Tag.find_or_create_by!(name: name.downcase)
      WikiHub::Tagging.create!(wiki_page_id: wiki_page_id, tag_id: tag.id)
    end
  end

  def tag_names_for(wiki_page_id)
    WikiHub::Tag.joins(:taggings).where(wiki_hub_taggings: { wiki_page_id: wiki_page_id }).order(:name).pluck(:name)
  end

  def permission_filter
    @permission_filter ||= WikiHub::PermissionFilter.new(User.current)
  end
end
