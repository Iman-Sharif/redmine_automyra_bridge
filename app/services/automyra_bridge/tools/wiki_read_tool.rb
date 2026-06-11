module AutomyraBridge
  module Tools
    class WikiReadTool < BaseTool
      NAME = 'wiki.read'.freeze
      LEGACY_ACTION_TYPE = 'read_wiki'.freeze
      DESCRIPTION = 'Read a wiki page in the current project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['wiki'], properties: { wiki: { type: 'object', required: ['title'], properties: { title: { type: 'string' } } } } }.freeze

      def required_permission
        :view_wiki_pages
      end

      def call(job, _user, input)
        page = wiki_page(job, input.dig('wiki', 'title')) || raise('Wiki page is not available.')
        { title: page.title, text: page.content&.text.to_s }
      end
    end
  end
end
