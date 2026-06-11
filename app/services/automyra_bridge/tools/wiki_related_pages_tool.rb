module AutomyraBridge
  module Tools
    class WikiRelatedPagesTool < WikiSearchTool
      NAME = 'wiki.related_pages'.freeze
      LEGACY_ACTION_TYPE = 'wiki_related_pages'.freeze
      DESCRIPTION = 'Find pages related to a wiki page title.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { wiki: { type: 'object', properties: { title: { type: 'string' } } }, limit: { type: 'integer' } } }.freeze

      def call(job, user, input)
        title = input.dig('wiki', 'title').to_s
        super(job, user, { 'query' => title, 'limit' => input['limit'] || 10 })
      end
    end
  end
end
