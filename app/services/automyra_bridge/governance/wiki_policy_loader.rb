module AutomyraBridge
  module Governance
    class WikiPolicyLoader
      MAX_STANDARD_TEXT_LENGTH = 12_000

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def self.context(**kwargs)
        new(**kwargs).context
      end

      def initialize(page_profile_id: nil, project: nil, title: nil)
        @page_profile_id = page_profile_id
        @project = project
        @title = title
      end

      def call
        return nil unless wiki_hub_available?

        snapshot&.searchable_text
      end

      def context
        return {} unless wiki_hub_available?

        page_snapshot = snapshot
        return {} unless page_snapshot

        {
          wiki_page_id: page_snapshot.wiki_page_id,
          page_snapshot_id: page_snapshot.id,
          title: page_snapshot.title,
          text: page_snapshot.searchable_text.to_s.first(MAX_STANDARD_TEXT_LENGTH)
        }
      end

      private

      def wiki_hub_available?
        defined?(WikiHub::PageProfile) && defined?(WikiHub::PageSnapshot)
      end

      def snapshot
        if @page_profile_id.present?
          profile = WikiHub::PageProfile.find_by(id: @page_profile_id)
          return nil unless profile

          WikiHub::PageSnapshot.find_by(wiki_page_id: profile.wiki_page_id)
        elsif @project && @title.present?
          WikiHub::PageSnapshot.find_by(project_id: @project.id, title: @title.to_s)
        end
      end
    end
  end
end
