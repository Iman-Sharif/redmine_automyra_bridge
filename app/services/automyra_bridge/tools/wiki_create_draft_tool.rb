module AutomyraBridge
  module Tools
    class WikiCreateDraftTool < WikiCreatePageTool
      NAME = 'wiki.create_draft'.freeze
      LEGACY_ACTION_TYPE = 'create_wiki_draft'.freeze
      DESCRIPTION = 'Create a draft wiki page in the current project.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = WikiCreatePageTool::INPUT_SCHEMA

      def call(job, user, input)
        attrs = (input['wiki'] || input).dup
        attrs['title'] = "Draft - #{attrs['title']}" unless attrs['title'].to_s.start_with?('Draft - ')
        super(job, user, { 'wiki' => attrs })
      end

      def verify!(result, _input)
        page = WikiPage.find_by(id: result[:page_id])
        raise 'Wiki draft verification failed.' unless page
        raise 'Wiki draft verification failed.' unless page.title.to_s.start_with?('Draft - ')
      end
    end
  end
end
