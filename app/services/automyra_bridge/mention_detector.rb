module AutomyraBridge
  class MentionDetector
    MENTION_PATTERN = /(^|\s)@(automyra|redmyra)\b/i

    def self.mentioned?(text)
      text.to_s.match?(MENTION_PATTERN)
    end
  end
end
