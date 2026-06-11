module AutomyraBridge
  module Governance
    module Executors
      class WikiTitleExecutor < BaseExecutor
        def call
          snapshot = WikiHub::PageSnapshot.find_by(id: action.object_id) if defined?(WikiHub::PageSnapshot)
          return fail_action!('Wiki page is no longer available.') unless snapshot
          page = snapshot.wiki_page
          return fail_action!('Wiki page is no longer available.') unless page

          ensure_permission!(:edit_wiki_pages, snapshot.project)
          ensure_current_value!(snapshot.title)
          return fail_action!('Wiki page title already exists.') if duplicate_title?(snapshot, page)

          rollback = { title: page.title, wiki_page_id: page.id }
          page.update!(title: finding.recommended_value)
          snapshot.update!(title: finding.recommended_value)
          apply_success!(rollback)
        rescue StandardError => e
          fail_action!(e.message)
        end

        private

        def duplicate_title?(snapshot, page)
          WikiPage.joins(:wiki)
                  .where(wikis: { project_id: snapshot.project_id })
                  .where('LOWER(wiki_pages.title) = ?', finding.recommended_value.to_s.downcase)
                  .where.not(id: page.id)
                  .exists?
        end
      end
    end
  end
end
