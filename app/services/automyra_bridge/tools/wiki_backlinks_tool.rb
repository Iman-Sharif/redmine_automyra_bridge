module AutomyraBridge
  module Tools
    class WikiBacklinksTool < BaseTool
      NAME = 'wiki.backlinks'.freeze
      LEGACY_ACTION_TYPE = 'wiki_backlinks'.freeze
      DESCRIPTION = 'Find wiki pages that link to a title.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = WikiReadTool::INPUT_SCHEMA

      def required_permission
        :view_wiki_pages
      end

      def call(job, _user, input)
        title = input.dig('wiki', 'title').to_s
        pages = WikiPage.joins(:wiki).left_outer_joins(:content).where(wikis: { project_id: job.project_id }).where('wiki_contents.text LIKE ?', "%[[#{title}%")
        { pages: pages.limit(10).map { |page| { id: page.id, title: page.title } } }
      end
    end
  end
end
