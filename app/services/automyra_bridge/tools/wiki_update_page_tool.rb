module AutomyraBridge
  module Tools
    class WikiUpdatePageTool < BaseTool
      NAME = 'wiki.update_page'.freeze
      LEGACY_ACTION_TYPE = 'update_wiki'.freeze
      DESCRIPTION = 'Update an existing wiki page in the current project.'.freeze
      RISK_LEVEL = 'destructive_soft'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['wiki'], properties: { wiki: { type: 'object', required: %w[title text], properties: { title: { type: 'string' }, text: { type: 'string' } } } } }.freeze

      def required_permission
        :edit_wiki_pages
      end

      def call(job, user, input)
        attrs = input['wiki'] || input
        page = wiki_page(job, attrs['title']) || raise('Wiki page is not available.')
        page.content ||= WikiContent.new(page: page)
        # Conflict safety: fail if someone else edited since last version
        if attrs['version'].present? && page.content.versions.count > 0 && page.content.versions.maximum(:version) > attrs['version'].to_i
          raise 'Wiki page has been updated by another user since version #{attrs["version"]}. Please reload the page and try again.'
        end
        page.content.text = attrs['text'].to_s
        page.content.author = user
        page.content.save!
        { page_id: page.id, title: page.title, version: page.content.versions.maximum(:version).to_i }
      end

      def verify!(result, input)
        raise "Wiki update did not return a valid page_id." unless result[:page_id].is_a?(Integer)
      end
    end
  end
end
