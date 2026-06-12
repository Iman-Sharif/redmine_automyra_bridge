module AutomyraBridge
  module Governance
    module Executors
      class WikiRequirementLinkExecutor < BaseExecutor
        def call
          snapshot = WikiHub::PageSnapshot.find_by(id: action.object_id) if defined?(WikiHub::PageSnapshot)
          return fail_action!('Wiki page is no longer available.') unless snapshot

          issue = requirement_issue
          return fail_action!('Requirement issue is no longer available.') unless issue

          ensure_permission!(:edit_wiki_pages, snapshot.project)
          existing = existing_link(snapshot, issue)
          return skip_duplicate!(existing) if existing

          rollback = { existing_relation_ids: existing_link_ids(snapshot), wiki_page_id: snapshot.wiki_page_id }
          link = WikiHub::PageLink.create!(
            source_page_id: snapshot.wiki_page_id,
            target_title: requirement_title(issue),
            target_project_id: issue.project_id,
            link_type: 'requirement',
            resolved: false
          )
          rollback[:created_relation_id] = link.id
          apply_success!(rollback)
        rescue StandardError => e
          fail_action!(e.message)
        end

        private

        def existing_link(snapshot, issue)
          WikiHub::PageLink.find_by(source_page_id: snapshot.wiki_page_id, link_type: 'requirement', target_title: requirement_title(issue))
        end

        def existing_link_ids(snapshot)
          WikiHub::PageLink.where(source_page_id: snapshot.wiki_page_id, link_type: 'requirement').pluck(:id)
        end

        def requirement_title(issue)
          "Issue ##{issue.id}"
        end

        def skip_duplicate!(link)
          action.update!(rollback_payload: { existing_relation_ids: [link.id], wiki_page_id: action.object_id }.to_json)
          ApplyResult.new(status: 'skipped', message: 'Requirement link already exists.', action: action)
        end
      end
    end
  end
end
