class WikiHubAdminController < ApplicationController
  before_action :require_admin

  def index
    @health = WikiHub::Healthcheck.call
    @orphan_count = WikiHub::PageLink.where(resolved: false).count
  end

  def rebuild
    render json: WikiHub::Indexer.rebuild_all
  end

  def health
    health = WikiHub::Healthcheck.call
    health[:details][:orphan_links] = WikiHub::PageLink.where(resolved: false).count
    render json: health
  end
end
