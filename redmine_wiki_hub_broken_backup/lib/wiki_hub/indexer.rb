module WikiHub
  class Indexer
    BATCH_SIZE = 100

    class << self
      def reindex_page(wiki_page)
        return default_page_result unless wiki_page

        project = wiki_page.wiki&.project
        return default_page_result unless project

        searchable_text = extract_searchable_text(wiki_page)

        link_entries = unique_link_entries(
          WikiHub::LinkParser.parse(searchable_text, source_project_id: project.id)
        )

        ActiveRecord::Base.transaction do
          snapshot = WikiHub::PageSnapshot.find_or_initialize_by(wiki_page_id: wiki_page.id)
          snapshot.assign_attributes(
            project_id: project.id,
            title: wiki_page.title.to_s,
            searchable_text: searchable_text,
            current_version_id: current_version_id_for(wiki_page)
          )
          snapshot.save!

          WikiHub::PageProfile.find_or_create_by!(wiki_page_id: wiki_page.id) do |profile|
            profile.page_kind = 'standard'
            profile.featured = false
          end

          replace_page_links!(wiki_page: wiki_page, link_entries: link_entries)
        end

        {
          pages_processed: 1,
          links_found: link_entries.size,
          errors: []
        }
      end

      def remove_page(wiki_page_or_id)
        wiki_page_id = wiki_page_or_id.respond_to?(:id) ? wiki_page_or_id.id : wiki_page_or_id
        return unless wiki_page_id

        WikiHub::PageLink.where(source_page_id: wiki_page_id).delete_all
        WikiHub::PageLink.where(target_page_id: wiki_page_id).update_all(target_page_id: nil, resolved: false)
        WikiHub::PageSnapshot.where(wiki_page_id: wiki_page_id).delete_all
        WikiHub::PageProfile.where(wiki_page_id: wiki_page_id).delete_all
      end

      def rebuild_all(batch_size: BATCH_SIZE)
        index_run = WikiHub::IndexRun.create!(started_at: Time.current, status: 'running', pages_processed: 0)
        results = {
          pages_total: WikiPage.count,
          pages_processed: 0,
          links_found: 0,
          errors: [],
          index_run_id: index_run.id
        }

        begin
          live_page_ids = []

          WikiPage.includes(:wiki, :content).find_in_batches(batch_size: batch_size) do |batch|
            batch.each do |wiki_page|
              unless indexable_page?(wiki_page)
                remove_page(wiki_page.id)
                next
              end

              live_page_ids << wiki_page.id
              page_result = reindex_page(wiki_page)
              results[:pages_processed] += page_result[:pages_processed]
              results[:links_found] += page_result[:links_found]
              results[:errors].concat(normalize_page_errors(wiki_page, page_result[:errors]))
            rescue StandardError => e
              results[:errors] << "wiki_page_id=#{wiki_page.id} #{e.class}: #{e.message}"
            end
          end

          cleanup_removed_pages!(live_page_ids)
          reconcile_unresolved_links!

          index_run.update!(
            status: results[:errors].any? ? 'failed' : 'completed',
            completed_at: Time.current,
            pages_processed: results[:pages_processed],
            error_message: results[:errors].presence&.join("\n")
          )
        rescue StandardError => e
          index_run.update!(
            status: 'failed',
            completed_at: Time.current,
            pages_processed: results[:pages_processed],
            error_message: e.message
          )
          raise
        end

        results
      end

      private

      def default_page_result
        { pages_processed: 0, links_found: 0, errors: [] }
      end

      def extract_searchable_text(wiki_page)
        text = wiki_page.content&.text.to_s
        [wiki_page.title.to_s, text].reject(&:blank?).join("\n\n")
      end

      def current_version_id_for(wiki_page)
        content = wiki_page.content
        return nil unless content

        content.versions.reorder(version: :desc).limit(1).pick(:id)
      end

      def replace_page_links!(wiki_page:, link_entries:)
        WikiHub::PageLink.where(source_page_id: wiki_page.id).delete_all
        link_entries.each do |link_entry|
          target_project_id = link_entry[:target_project_id]
          target_title = link_entry[:target_title]
          target_page = find_target_page(target_project_id: target_project_id, target_title: target_title)

          WikiHub::PageLink.create!(
            source_page_id: wiki_page.id,
            target_page_id: target_page&.id,
            target_project_id: target_project_id,
            target_title: target_title,
            resolved: target_page.present?,
            link_type: 'wiki'
          )
        end
      end

      def find_target_page(target_project_id:, target_title:)
        return nil if target_project_id.blank? || target_title.blank?

        WikiPage.joins(:wiki)
                .where(wikis: { project_id: target_project_id })
                .where('LOWER(wiki_pages.title) = ?', target_title.downcase)
                .first
      end

      def unique_link_entries(link_entries)
        Array(link_entries).uniq do |link_entry|
          [link_entry[:target_project_id], link_entry[:target_title].to_s.downcase, 'wiki']
        end
      end

      def indexable_page?(wiki_page)
        wiki_page.present? && wiki_page.wiki&.project.present?
      end

      def normalize_page_errors(wiki_page, page_errors)
        Array(page_errors).filter_map do |page_error|
          next if page_error.blank?

          "wiki_page_id=#{wiki_page.id} #{page_error}"
        end
      end

      def cleanup_removed_pages!(live_page_ids)
        live_page_ids = Array(live_page_ids).compact.uniq
        stale_snapshot_scope = WikiHub::PageSnapshot.where.not(wiki_page_id: live_page_ids)
        stale_snapshot_ids = stale_snapshot_scope.pluck(:wiki_page_id)
        stale_profile_scope = WikiHub::PageProfile.where.not(wiki_page_id: live_page_ids)
        stale_profile_ids = stale_profile_scope.pluck(:wiki_page_id)
        stale_ids = (stale_snapshot_ids + stale_profile_ids).uniq

        stale_snapshot_scope.delete_all
        stale_profile_scope.delete_all
        WikiHub::PageLink.where(source_page_id: stale_ids).delete_all if stale_ids.any?
        WikiHub::PageLink.where(target_page_id: stale_ids).update_all(target_page_id: nil, resolved: false) if stale_ids.any?
        WikiHub::PageLink.where.not(source_page_id: live_page_ids).delete_all
        WikiHub::PageLink.where.not(target_page_id: [nil] + live_page_ids).update_all(target_page_id: nil, resolved: false)
      end

      def reconcile_unresolved_links!
        WikiHub::PageLink.where(resolved: false).find_each do |link|
          target_page = find_target_page(target_project_id: link.target_project_id, target_title: link.target_title)
          next unless target_page

          link.update!(target_page_id: target_page.id, resolved: true)
        end
      end
    end
  end
end
