module AutomyraBridge
  module Tools
    class WikiCreatePageTool < BaseTool
      NAME = 'wiki.create_page'.freeze
      LEGACY_ACTION_TYPE = 'create_wiki_page'.freeze
      DESCRIPTION = 'Create a wiki page in the current project.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['wiki'], properties: { wiki: { type: 'object', required: %w[title text], properties: { title: { type: 'string' }, text: { type: 'string' } } } } }.freeze

      def required_permission
        :edit_wiki_pages
      end

      def call(job, user, input)
        attrs = input['wiki'] || input
        raise 'Wiki title is blank.' if attrs['title'].to_s.strip.blank?
        raise 'Wiki page already exists.' if wiki_page(job, attrs['title'])

        page = WikiPage.new(wiki: project_wiki(job), title: attrs['title'])
        page.content = WikiContent.new(page: page, text: attrs['text'].to_s, author: user)
        page.save!
        { page_id: page.id, title: page.title }
      end
    end
  end
end
