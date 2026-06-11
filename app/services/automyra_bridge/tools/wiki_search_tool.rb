module AutomyraBridge
  module Tools
    class WikiSearchTool < BaseTool
      NAME = 'wiki.search'.freeze
      LEGACY_ACTION_TYPE = 'search_wiki'.freeze
      DESCRIPTION = 'Search wiki pages in the current project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } } }.freeze

      def required_permission
        :view_wiki_pages
      end

      def call(job, _user, input)
        query = input['query'].to_s.strip.downcase
        limit = [[input['limit'].to_i, 1].max, 10].min
        pages = WikiPage.joins(:wiki).left_outer_joins(:content).where(wikis: { project_id: job.project_id }).order(:title)
        pages = pages.where('LOWER(wiki_pages.title) LIKE :q OR LOWER(wiki_contents.text) LIKE :q', q: "%#{query}%") if query.present?
        { pages: pages.limit(limit).map { |page| { id: page.id, title: page.title } } }
      end
    end
  end
end
