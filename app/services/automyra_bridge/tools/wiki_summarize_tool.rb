module AutomyraBridge
  module Tools
    class WikiSummarizeTool < BaseTool
      NAME = 'wiki.summarize'.freeze
      LEGACY_ACTION_TYPE = 'summarize_wiki'.freeze
      DESCRIPTION = 'Summarize a wiki page in the current project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = WikiReadTool::INPUT_SCHEMA

      def required_permission
        :view_wiki_pages
      end

      def call(job, _user, input)
        page = wiki_page(job, input.dig('wiki', 'title')) || raise('Wiki page is not available.')
        text = page.content&.text.to_s
        { title: page.title, summary: text.split(/\n{2,}/).first(3).join("\n\n").truncate(1000) }
      end
    end
  end
end
