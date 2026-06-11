# frozen_string_literal: true

module AutomyraBridge
  class ActivityLogWikiGenerator
    PROJECT_IDENTIFIER = 'automyre'
    DAILY_TITLE_FORMAT = 'Automyra_-_Log_-_%Y-%m-%d'
    INDEX_TITLE = 'Automyra_-_Log_-_activity'
    INDEX_DAYS = 30

    class << self
      def generate_daily_page(date)
        date = date.to_date
        entries = AutomyraBridgeActivityLog.for_date(date).order(occurred_at: :desc)
        return nil if entries.empty?

        project = Project.find_by!(identifier: PROJECT_IDENTIFIER)
        wiki = project.wiki || Wiki.create!(project: project, start_page: 'Wiki')
        title = date.strftime(DAILY_TITLE_FORMAT)
        text = render_daily_page(date, entries)

        page = wiki.find_or_new_page(title)
        page.content ||= WikiContent.new
        page.content.text = text
        page.content.author = admin_user
        page.content.comments = "Activity log generated for #{date.iso8601}"
        page.save!
        page.content.save!

        set_page_profile!(page)
        page
      end

      def generate_index_page
        project = Project.find_by!(identifier: PROJECT_IDENTIFIER)
        wiki = project.wiki || Wiki.create!(project: project, start_page: 'Wiki')

        daily_pages = existing_daily_pages(wiki)
        return nil if daily_pages.empty?

        text = render_index_page(daily_pages)
        page = wiki.find_or_new_page(INDEX_TITLE)
        page.content ||= WikiContent.new
        page.content.text = text
        page.content.author = admin_user
        page.content.comments = 'Activity log index updated'
        page.save!
        page.content.save!

        set_page_profile!(page)
        page
      end

      private

      def render_daily_page(date, entries)
        lines = []
        lines << "# Automyra Activity Log — #{date.iso8601}"
        lines << ''
        lines << "> Generated automatically. #{entries.size} entries."
        lines << ''

        entries.each do |entry|
          time_str = entry.occurred_at.strftime('%H:%M')
          lines << "### #{time_str} — #{entry.action_type}: #{entry.summary}"

          meta_parts = []
          meta_parts << "Source: `#{entry.source}`" if entry.source.present?
          meta_parts << "Target: #{format_target(entry)}" if entry.target_type.present? || entry.target_id.present?
          meta_parts << "Session: #{entry.session_id}" if entry.session_id.present?

          lines << meta_parts.join(' | ') if meta_parts.any?
          lines << ''
        end

        lines.join("\n")
      end

      def render_index_page(daily_pages)
        lines = []
        lines << '# Automyra Activity Log'
        lines << ''
        lines << '> Chronological record of all Automyra actions. Updated daily.'
        lines << ''
        lines << '| Date | Entries | Link |'
        lines << '|------|---------|------|'

        daily_pages.each do |info|
          lines << "| #{info[:date]} | #{info[:count]} | [[#{info[:title]}]] |"
        end

        lines << ''
        lines.join("\n")
      end

      def format_target(entry)
        target_type = entry.target_type.to_s.downcase
        target_id = entry.target_id

        case target_type
        when 'issue'
          "##{target_id}"
        when 'task', 'taskhub::task'
          "task##{target_id}"
        when 'wikipage', 'wiki_page'
          "[[#{target_id}]]"
        else
          target_id.present? ? "#{target_type}##{target_id}" : target_type
        end
      end

      def existing_daily_pages(wiki)
        dates = (INDEX_DAYS - 1).downto(0).map { |i| Date.current - i }
        results = []

        dates.reverse_each do |date|
          title = date.strftime(DAILY_TITLE_FORMAT)
          page = wiki.pages.find_by(title: title)
          next unless page

          count = AutomyraBridgeActivityLog.for_date(date).count
          results << { date: date.iso8601, title: title, count: count }
        end

        results
      end

      def set_page_profile!(page)
        profile = WikiHub::PageProfile.find_or_initialize_by(wiki_page_id: page.id)
        profile.page_kind = 'activity_log'
        profile.featured = false
        profile.save!
      end

      def admin_user
        User.find_by(login: 'admin') || User.first
      end
    end
  end
end
