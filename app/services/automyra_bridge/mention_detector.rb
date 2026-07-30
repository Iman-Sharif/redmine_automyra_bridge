module AutomyraBridge
  class MentionDetector
    MENTION_PATTERN = /(^|\s)@(automyra|redmyra)\b/i
    DEFAULT_MR_T_PATTERN = 'mrt'.freeze

    def self.mentioned?(text)
      mention_target(text).present?
    end

    def self.mention_target(text)
      text = text.to_s
      return :automyra if text.match?(MENTION_PATTERN)
      return :mr_t if text.match?(mr_t_pattern)

      nil
    end

    def self.mr_t_pattern
      custom = mr_t_setting
      /(^|\s)@#{Regexp.escape(custom)}\b/i
    end

    def self.mr_t_setting
      settings = Setting.plugin_redmine_automyra_bridge
      value = settings.is_a?(Hash) ? settings['mr_t_mention_pattern'] : nil
      value.to_s.strip.presence || DEFAULT_MR_T_PATTERN
    rescue StandardError
      DEFAULT_MR_T_PATTERN
    end
  end
end
