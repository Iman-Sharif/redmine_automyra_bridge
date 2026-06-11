module AutomyraBridge
  module Governance
    module Collectors
      class WikiPageCollector < BaseCollector
        def self.call(**kwargs)
          new(**kwargs).call
        end

        def call
          return [] unless (project || policy&.global?) && defined?(WikiHub::PageSnapshot)

          active_project_scope(WikiHub::PageSnapshot.all, :wiki_hub_page_snapshots)
            .order(:id)
            .limit(limit * 2)
            .each_with_object([]) do |snapshot, candidates|
              next if excluded?(snapshot.title)

              candidates << candidate(snapshot)
              break candidates if candidates.size >= limit
            end
        end

        private

        def candidate(snapshot)
          {
            object_type: 'WikiHub::PageSnapshot',
            object_id: snapshot.id,
            wiki_page_id: snapshot.wiki_page_id,
            title: snapshot.title,
            project_id: snapshot.project_id,
            current_value: snapshot.title,
            page_text: snapshot.searchable_text.to_s.first(4_000)
          }
        end
      end
    end
  end
end
