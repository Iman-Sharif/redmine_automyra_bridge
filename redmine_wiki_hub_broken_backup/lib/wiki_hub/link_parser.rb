module WikiHub
  class LinkParser
    WIKI_LINK_PATTERN = /\[\[([^\[\]]+)\]\]/.freeze
    CROSS_PROJECT_PATTERN = /\A@(?<project_identifier>[a-z0-9][a-z0-9\-_]*)\/(?<title>.+)\z/i.freeze

    class << self
      def parse(text, source_project_id:)
        return [] if text.blank?

        text.to_s.scan(WIKI_LINK_PATTERN).filter_map do |(inner_text)|
          parse_token(inner_text.to_s, source_project_id: source_project_id)
        end
      end

      private

      def parse_token(raw_token, source_project_id:)
        token = normalize_token(raw_token)
        return nil if token.blank?

        cross_project_match = token.match(CROSS_PROJECT_PATTERN)
        if cross_project_match
          project = Project.find_by(identifier: cross_project_match[:project_identifier].downcase)
          title = normalize_title(cross_project_match[:title])
          return nil if title.blank?

          return {
            target_project_id: project&.id,
            target_title: title,
            raw_text: raw_token.strip
          }
        end

        return nil if token.start_with?('@')

        title = normalize_title(token)
        return nil if title.blank?

        {
          target_project_id: source_project_id,
          target_title: title,
          raw_text: raw_token.strip
        }
      rescue StandardError
        nil
      end

      def normalize_token(raw_token)
        raw_token.to_s.split('|', 2).first.to_s.strip
      end

      def normalize_title(title)
        title.to_s.strip.gsub(/\s+/, ' ')
      end
    end
  end
end
