class WikiHubGraphController < ApplicationController
  before_action :require_login
  before_action :set_cache_headers, only: [:index]

  MAX_NODES = 150
  MAX_EDGES = 300

  def index
    @root_page_id = params[:root_page_id].presence || default_root_page_id
    @graph = WikiHub::GraphService.new(User.current).call(
      root_page_id: @root_page_id,
      max_nodes: MAX_NODES,
      max_edges: MAX_EDGES
    )

    respond_to do |format|
      format.html
      format.json { render json: @graph }
    end
  end

  private

  def default_root_page_id
    WikiHub::PageUniverseService.new(User.current).visible_pages.order(:wiki_page_id).limit(1).pick(:wiki_page_id)
  end

  def set_cache_headers
    response.headers['Cache-Control'] = 'private, max-age=300'
    response.headers['Expires'] = 5.minutes.from_now.httpdate
  end
end
